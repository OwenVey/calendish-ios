import CryptoKit
import GoogleSignIn
import Supabase
import SwiftUI

/// The production adapter owns SDK auth, pagination, query shapes, storage, and private broadcasts.
@MainActor
final class SupabaseHouseholdBackend: HouseholdBackend {
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? supabase }
    var groceryTransport: (any GrocerySyncTransport)? { SupabaseGroceryTransport(client: client) }
    var aisleClassifier: (([String]) async -> [String: String])? {
        { await GroceryAisleClassifier.aisles(for: $0).mapValues(\.rawValue) }
    }
    private func account(_ user: User) -> HouseholdAccount {
        let metadata = user.userMetadata
        var name = ""
        if case let .string(value)? = metadata["display_name"], !value.isEmpty { name = value }
        else if case let .string(value)? = metadata["full_name"] ?? metadata["name"] { name = value.components(separatedBy: " ").first ?? value }
        var avatar: URL?
        if case let .string(value)? = metadata["avatar_url"] ?? metadata["picture"] { avatar = URL(string: value) }
        return HouseholdAccount(id: user.id, email: user.email, displayName: name, avatarURL: avatar)
    }
    var account: HouseholdAccount? { client.auth.currentUser.map(account) }
    var authChanges: AsyncStream<HouseholdAuthChange> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    if let session, session.isExpired { continue }
                    if session == nil { GIDSignIn.sharedInstance.signOut() }
                    continuation.yield(HouseholdAuthChange(account: session.map { account($0.user) }, passwordRecovery: event == .passwordRecovery))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func authenticate(_ credentials: HouseholdCredentials) async throws -> Bool {
        switch credentials {
        case let .email(email, password): try await client.auth.signIn(email: email, password: password)
        case let .signUp(email, password): return try await client.auth.signUp(email: email, password: password).session != nil
        case .google: try await signInWithGoogle()
        case .password(let password): try await client.auth.update(user: UserAttributes(password: password))
        case .passwordReset(let email): try await client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "calendish://login-callback"))
        }
        return true
    }
    func signOut() async throws { try await client.auth.signOut() }
    func currentHousehold(user: UUID) async throws -> HouseholdRecord? {
        let memberships: [MemberRecord] = try await client.from("household_members").select().eq("user_id", value: user).execute().value
        guard let id = memberships.first?.householdID else { return nil }
        return try await client.from("households").select().eq("id", value: id).single().execute().value
    }
    func startHousehold(name: String, code: String?) async throws -> HouseholdRecord {
        try await client.rpc("start_household", params: StartHouseholdParameters(member_name: name, code: code)).execute().value
    }
    func snapshot(household id: UUID) async throws -> HouseholdSnapshot {
        async let hs: [HouseholdRecord] = client.from("households").select().eq("id", value: id).execute().value
        async let memberRows: [MemberRecord] = fetchRows("household_members", householdID: id, idColumn: "user_id", key: \.userID)
        // RLS selects the person's originals, household recipes, and members' shared recipes.
        async let recipeRows: [RecipeRecord] = fetchRows("recipes", key: \.id)
        async let favoriteRows: [FavoriteRecord] = fetchRows("recipe_favorites", idColumn: "recipe_id", key: \.recipeID)
        async let mealRows: [PlannedMealRecord] = fetchRows("planned_meals", householdID: id, key: \.id)
        async let noteRows: [MealPlanNoteRecord] = fetchRows("meal_plan_notes", householdID: id, key: \.id)
        async let reviewRows: [RecipeReviewRecord] = fetchRows("recipe_reviews", key: \.id)
        async let cookRows: [RecipeCookRecord] = fetchRows("recipe_cooks", householdID: id, key: \.id)
        let (h, m, r, f, p, n, v, c) = try await (hs, memberRows, recipeRows, favoriteRows, mealRows, noteRows, reviewRows, cookRows)
        let favorites = Set(f.map(\.recipeID))
        return HouseholdSnapshot(household: h.first?.household,
            members: m.sorted { ($0.role == "owner" ? 0 : 1, $0.joinedAt ?? .distantPast) < ($1.role == "owner" ? 0 : 1, $1.joinedAt ?? .distantPast) }
                .map { HouseholdMember(userID: $0.userID, displayName: $0.displayName, role: $0.role, avatarURL: $0.avatarURL.flatMap(URL.init)) },
            recipes: r.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.map { Recipe($0, favorites: favorites) },
            meals: p.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }.compactMap(PlannedMeal.init),
            notes: n.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }.compactMap(MealPlanNote.init),
            reviews: v.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }.map(RecipeReview.init),
            cooks: c.compactMap(RecipeCook.init))
    }
    func write(_ mutation: HouseholdMutation) async throws {
        switch mutation {
        case let .renameHousehold(id, name):
            try await client.from("households").update(["name": name]).eq("id", value: id).execute()
        case let .groceryAutoClear(id, setting):
            try await client.from("households").update(["grocery_auto_clear": setting.rawValue]).eq("id", value: id).execute()
        case let .renameMember(household, user, name):
            try await client.from("household_members").update(["display_name": name]).eq("household_id", value: household).eq("user_id", value: user).execute()
        case let .avatar(household, user, url):
            let rows: [MemberRecord] = try await client.from("household_members").update(["avatar_url": url.absoluteString])
                .eq("household_id", value: household).eq("user_id", value: user).select().execute().value
            guard rows.count == 1 else { throw CocoaError(.fileWriteNoPermission) }
        case let .transferOwnership(household, user):
            try await client.rpc("transfer_household_ownership", params: TransferOwnershipParameters(target_household: household, new_owner: user)).execute()
        case let .removeMember(household, user):
            try await client.rpc("remove_household_member", params: ["target_household": household, "target_user": user]).execute()
        case let .saveRecipe(recipe, isNew, upload, stalePhoto):
            if let upload { try await uploadPhoto(upload, bucket: .recipe) }
            try Task.checkCancellation()
            if isNew {
                guard let owner = recipe.owner?.person else { throw CocoaError(.fileWriteNoPermission) }
                try await client.from("recipes").insert(NewRecipeRecord(id: recipe.id, ownerID: owner, isShared: recipe.owner?.isShared ?? true, content: recipe.content)).execute()
            } else { try await client.from("recipes").update(recipe.content).eq("id", value: recipe.id).execute() }
            try Task.checkCancellation()
            if let stalePhoto { await removePhotos([stalePhoto], bucket: .recipe) }
        case .deleteRecipe(let id):
            let paths: [String] = try await client.rpc("delete_recipe", params: ["target_recipe": id]).execute().value
            await removePhotos(paths, bucket: .recipe)
        case let .sharing(id, shared):
            try await client.rpc("set_recipe_sharing", params: RecipeSharingParameters(target_recipe: id, shared: shared)).execute()
        case let .favorite(recipe, user, enabled):
            if enabled {
                try await client.from("recipe_favorites").upsert(FavoriteRecord(recipeID: recipe), onConflict: "user_id,recipe_id", returning: .minimal, ignoreDuplicates: true).execute()
            } else { try await client.from("recipe_favorites").delete().eq("user_id", value: user).eq("recipe_id", value: recipe).execute() }
        case .review(let review):
            if review.isEmpty { try await client.from("recipe_reviews").delete().eq("user_id", value: review.userID).eq("recipe_id", value: review.recipeID).execute() }
            else { try await client.from("recipe_reviews").upsert(review.record, onConflict: "user_id,recipe_id", returning: .minimal).execute() }
        case let .markCooked(household, recipe, day):
            try await client.from("recipe_cooks").upsert(RecipeCookRecord(householdID: household, recipeID: recipe, cookedOn: DayFormat.string(from: day)),
                onConflict: "household_id,recipe_id,cooked_on", returning: .minimal, ignoreDuplicates: true).execute()
        case let .removeCooked(household, recipe, day):
            try await client.from("recipe_cooks").delete().eq("household_id", value: household).eq("recipe_id", value: recipe).eq("cooked_on", value: DayFormat.string(from: day)).execute()
        case let .saveMeal(meal, household, keepVersion):
            let parameters = SaveMealParameters(target_household: household, meal_id: meal.id, meal_date: DayFormat.string(from: meal.date),
                meal_recipe: keepVersion ? nil : meal.recipeID, meal_servings: meal.servings, keep_version: keepVersion)
            try await client.rpc("save_planned_meal", params: parameters).execute()
        case .updateMeal(let id): try await client.rpc("update_planned_meal_to_latest", params: ["target_meal": id]).execute()
        case .removeMeals(let ids): try await client.from("planned_meals").delete().in("id", values: ids).execute()
        case let .saveNote(note, household): try await client.from("meal_plan_notes").upsert(note.record(household: household)).execute()
        case .removeNote(let id): try await client.from("meal_plan_notes").delete().eq("id", value: id).execute()
        }
    }
    func addMeal(_ meal: PlannedMeal, household: UUID, expectedRevision: Int) async throws -> PlannedMealAddition {
        guard let recipe = meal.recipeID else { return .unavailable }
        let parameters = AddMealParameters(target_household: household, meal_id: meal.id, meal_date: DayFormat.string(from: meal.date),
            meal_recipe: recipe, expected_revision: expectedRevision, meal_servings: meal.servings)
        return try await client.rpc("add_planned_meal", params: parameters).execute().value
    }
    func previewMove(code: String?) async throws -> HouseholdMovePreview {
        try await client.rpc("preview_household_move", params: PreviewMoveParameters(code: code)).execute().value
    }
    func move(code: String?, saveRecipes: Bool, expected: UUID?) async throws -> HouseholdMoveResult {
        do {
            if let code {
                return try await client.rpc("join_household", params: JoinHouseholdParameters(code: code, save_household_recipes: saveRecipes, expected_household: expected)).execute().value
            }
            return try await client.rpc("leave_household", params: LeaveHouseholdParameters(save_household_recipes: saveRecipes, expected_household: expected)).execute().value
        } catch let error as PostgrestError { throw HouseholdMoveRejected(underlying: error) }
    }
    func copyRecipe(_ id: UUID) async throws -> Recipe {
        let row: RecipeRecord = try await client.rpc("save_recipe_copy", params: ["source_recipe": id]).execute().value
        return Recipe(row)
    }
    func deleteHouseholdData(_ id: UUID) async throws -> [String] {
        try await client.rpc("delete_household_data", params: ["target_household": id]).execute().value
    }
    func deleteAccount(_ user: UUID) async throws {
        let paths: [String] = try await client.rpc("delete_account").execute().value
        // The token remains valid long enough to clean up unreferenced storage after the RPC.
        await removePhotos(paths, bucket: .recipe)
        let folder = user.uuidString.lowercased()
        if let avatars = try? await client.storage.from(ProfilePhotos.bucket).list(path: folder), !avatars.isEmpty {
            await removePhotos(avatars.map { "\(folder)/\($0.name)" }, bucket: .profile)
        }
        try? await client.auth.signOut(scope: .local)
    }
    func uploadPhoto(_ upload: HouseholdPhotoUpload, bucket: HouseholdPhotoBucket) async throws {
        try await client.storage.from(bucket.rawValue).upload(upload.path, data: upload.data,
            options: FileOptions(cacheControl: bucket == .recipe ? "31536000" : "0", contentType: "image/jpeg"))
    }
    func removePhotos(_ paths: [String], bucket: HouseholdPhotoBucket) async {
        for start in stride(from: 0, to: paths.count, by: 100) {
            _ = try? await client.storage.from(bucket.rawValue).remove(paths: Array(paths[start..<min(start + 100, paths.count)]))
        }
    }
    func avatar(household: UUID, user: UUID) async throws -> URL? {
        let rows: [MemberRecord] = try await client.from("household_members").select().eq("household_id", value: household).eq("user_id", value: user).execute().value
        return rows.first?.avatarURL.flatMap(URL.init)
    }
    func subscribe(household: UUID, user: UUID) async -> any HouseholdSubscription {
        let subscription = SupabaseHouseholdSubscription(client: client, household: household, user: user)
        await subscription.start()
        return subscription
    }
    private func signInWithGoogle() async throws {
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        // Google embeds the hashed nonce in the token; Supabase checks it against the raw value.
        let nonce = Self.randomNonce()
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: Self.sha256(nonce))
        } catch let error as GIDSignInError where error.code == .canceled {
            return
        }
        guard let idToken = result.user.idToken?.tokenString else { throw URLError(.userAuthenticationRequired) }
        try await client.auth.signInWithIdToken(credentials: .init(
            provider: .google, idToken: idToken, accessToken: result.user.accessToken.tokenString, nonce: nonce))
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fetchRows<Row: Decodable>(_ table: String, householdID: UUID? = nil,
                                           idColumn: String = "id", key: KeyPath<Row, UUID>) async throws -> [Row] {
        var rows: [Row] = []
        var cursor: UUID?
        let pageSize = 500
        while true {
            try Task.checkCancellation()
            var query = client.from(table).select()
            if let householdID { query = query.eq("household_id", value: householdID) }
            if let cursor { query = query.gt(idColumn, value: cursor) }
            let page: [Row] = try await query.order(idColumn).limit(pageSize).execute().value
            rows.append(contentsOf: page)
            guard page.count == pageSize, let last = page.last else { return rows }
            cursor = last[keyPath: key]
        }
    }
}
