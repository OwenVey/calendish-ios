import SwiftUI
import Observation
import Supabase
import GoogleSignIn
import CryptoKit

/// The signed-in user's household and its shared recipes, meal plan, and grocery list.
/// Edits apply locally right away, then save to Supabase; changes from other members arrive over Realtime.
@Observable
final class HouseholdStore {
    enum Phase: Equatable {
        case loading, signedOut, needsHousehold, ready
    }

    private(set) var phase: Phase = .loading
    private(set) var household: Household?
    private(set) var members: [HouseholdMember] = []
    private(set) var userID: UUID?
    var recipes: [Recipe] = []
    var meals: [PlannedMeal] = []
    var groceries: [GroceryItem] { grocerySync.items }
    var planningDate = Calendar.current.startOfDay(for: Date.now)
    /// The latest failed save or load, shown as an alert.
    var errorMessage: String?
    var needsPasswordReset = false

    private let isPreview: Bool
    private var channel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var realtimeConnectionTask: Task<Void, Never>?
    private var realtimeStarting = false
    private var writeTask: Task<Void, Never>?
    private var savingTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingWrites = 0
    private var writeRevision: UInt64 = 0
    private var realtimeStatusTask: Task<Void, Never>?
    @ObservationIgnored private lazy var grocerySync = GrocerySync(
        transport: isPreview ? nil : SupabaseGroceryTransport(),
        onChange: { [weak self] in self?.sortGroceriesIntoAisles() },
        onError: { [weak self] error in self?.report(error) })
    private var aisleTask: Task<Void, Never>?
    /// The name each item was last sorted under, so a failed save isn't retried on every refetch.
    private var sortedNames: [UUID: String] = [:]
    private var syncSession = UUID()

    init() { isPreview = false }

    /// Sample content with no account or network, for SwiftUI previews.
    static func preview() -> HouseholdStore {
        let store = HouseholdStore(previewing: true)
        let today = Calendar.current.startOfDay(for: .now)
        let recipes = SampleRecipes.all
        store.phase = .ready
        store.household = Household(id: UUID(), name: "Our household", inviteCode: "PREVIEW1")
        store.members = [HouseholdMember(userID: UUID(), displayName: "Owen", role: "owner")]
        store.recipes = recipes
        store.meals = [
            PlannedMeal(date: today, slot: .breakfast, recipeID: recipes[2].id, servings: 2),
            PlannedMeal(date: today, slot: .dinner, recipeID: recipes[0].id, servings: 4),
            PlannedMeal(date: Calendar.current.date(byAdding: .day, value: 1, to: today)!, slot: .dinner, recipeID: recipes[1].id, servings: 4)
        ]
        store.grocerySync.setHousehold(store.household?.id, items: [
            GroceryItem(name: "Cherry tomatoes", amount: "2 cups", source: "Lemon & herb orzo", position: 0),
            GroceryItem(name: "Orzo", amount: "1½ cups", source: "Lemon & herb orzo", position: 1),
            GroceryItem(name: "Greek yogurt", amount: "1 tub", source: "General", position: 2),
            GroceryItem(name: "Olive oil", amount: "2 tbsp", source: "Lemon & herb orzo", isComplete: true, position: 3)
        ])
        return store
    }

    private init(previewing: Bool) { isPreview = previewing }

    var remainingGroceries: Int { groceries.filter { !$0.isComplete }.count }
    var currentMember: HouseholdMember? { members.first { $0.userID == userID } }
    func recipe(for meal: PlannedMeal) -> Recipe? { recipes.first { $0.id == meal.recipeID } }
    /// Every tag in the recipe book, sorted, with tags that differ only by case folded together.
    var recipeTags: [String] {
        var seen = Set<String>()
        return recipes.flatMap(\.tags).filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    func meal(on date: Date, slot: MealSlot) -> PlannedMeal? {
        meals.first { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.slot == slot }
    }

    // MARK: Session

    /// Follows sign-in state for the life of the app.
    func start() async {
        guard !isPreview else { return }
        for await (event, session) in supabase.auth.authStateChanges {
            if let session {
                // A stored session can start out expired; the client refreshes it and emits again.
                if session.isExpired { continue }
                CookingSession.shared.setAccount(session.user.id)
                if userID != session.user.id {
                    await resetAccountData()
                    userID = session.user.id
                    await loadHousehold()
                }
                if event == .passwordRecovery { needsPasswordReset = true }
            } else {
                CookingSession.shared.setAccount(nil)
                await resetAccountData()
                GIDSignIn.sharedInstance.signOut()
                userID = nil
                phase = .signedOut
            }
        }
    }

    /// Invalidates in-flight reads/writes before awaiting channel teardown.
    private func resetAccountData() async {
        phase = .loading
        syncSession = UUID()
        for task in savingTasks.values { task.cancel() }
        savingTasks.removeAll()
        writeTask?.cancel(); writeTask = nil
        aisleTask?.cancel(); aisleTask = nil
        sortedNames = [:]
        pendingWrites = 0
        writeRevision &+= 1
        grocerySync.setHousehold(nil)
        needsPasswordReset = false
        household = nil
        members = []; recipes = []; meals = []
        RecipePhotos.shared.clearCache()
        await stopRealtime()
    }

    /// Signs in with Google's native sheet and hands the ID token to Supabase. Does nothing if the person cancels.
    func signInWithGoogle() async throws {
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
        try await supabase.auth.signInWithIdToken(credentials: .init(
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

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    /// Returns false when Supabase wants the email confirmed before the first sign-in.
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(email: email, password: password)
        return response.session != nil
    }

    func signOut() async {
        do { try await supabase.auth.signOut() } catch { report(error) }
    }

    func createHousehold(name: String, memberName: String) async throws {
        let row: HouseholdRecord = try await supabase
            .rpc("create_household", params: ["household_name": name, "member_name": memberName])
            .execute().value
        try await enter(row)
    }

    func joinHousehold(code: String, memberName: String) async throws {
        let row: HouseholdRecord = try await supabase
            .rpc("join_household", params: ["code": code, "member_name": memberName])
            .execute().value
        try await enter(row)
    }

    func renameHousehold(to name: String) {
        guard let id = household?.id, !name.isEmpty, name != household?.name else { return }
        household?.name = name
        save { try await supabase.from("households").update(["name": name]).eq("id", value: id).execute() }
    }

    func renameMember(to name: String) {
        guard let householdID = household?.id, let userID, !name.isEmpty, name != currentMember?.displayName,
              let index = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[index].displayName = name
        save {
            try await supabase.from("household_members").update(["display_name": name])
                .eq("household_id", value: householdID).eq("user_id", value: userID).execute()
        }
    }

    /// The name given at sign-up, or the first name from Google.
    var suggestedDisplayName: String {
        guard !isPreview, let metadata = supabase.auth.currentUser?.userMetadata else { return "" }
        if case let .string(name)? = metadata["display_name"], !name.isEmpty { return name }
        if case let .string(name)? = metadata["full_name"] ?? metadata["name"] {
            return name.components(separatedBy: " ").first ?? name
        }
        return ""
    }

    /// The email on the signed-in account, if it has one.
    var accountEmail: String? {
        guard !isPreview else { return "owen@example.com" }
        return supabase.auth.currentUser?.email
    }

    private func loadHousehold() async {
        phase = .loading
        do {
            // Membership rows only include households this user belongs to.
            let memberships: [MemberRecord] = try await supabase.from("household_members")
                .select().eq("user_id", value: userID!).order("joined_at").limit(1).execute().value
            guard let householdID = memberships.first?.householdID else {
                phase = .needsHousehold
                return
            }
            let row: HouseholdRecord = try await supabase.from("households")
                .select().eq("id", value: householdID).single().execute().value
            try await enter(row)
        } catch {
            report(error)
            phase = .needsHousehold
        }
    }

    func updatePassword(_ password: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: password))
        needsPasswordReset = false
    }

    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: URL(string: "calendish://login-callback"))
    }

    private func enter(_ row: HouseholdRecord) async throws {
        household = Household(id: row.id, name: row.name, inviteCode: row.inviteCode)
        grocerySync.setHousehold(row.id)
        try await reload()
        phase = .ready
        syncAvatar()
        await startRealtime()
    }

    /// Copies the Google profile photo onto this member's row so the rest of the household can see it.
    private func syncAvatar() {
        guard let householdID = household?.id, let userID,
              case let .string(avatar)? = supabase.auth.currentUser?.userMetadata["avatar_url"] ?? supabase.auth.currentUser?.userMetadata["picture"],
              let url = URL(string: avatar), currentMember?.avatarURL != url,
              let index = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[index].avatarURL = url
        save {
            try await supabase.from("household_members").update(["avatar_url": avatar])
                .eq("household_id", value: householdID).eq("user_id", value: userID).execute()
        }
    }

    // MARK: Loading

    /// Fetches everything for the household. The data set is small enough to refetch whole.
    func reload() async throws {
        guard !isPreview, let id = household?.id else { return }
        let session = syncSession
        let revision = writeRevision
        async let householdRows: [HouseholdRecord] = supabase.from("households").select().eq("id", value: id).execute().value
        async let memberRows: [MemberRecord] = fetchRows("household_members", householdID: id, idColumn: "user_id", key: \.userID)
        async let recipeRows: [RecipeRecord] = fetchRows("recipes", householdID: id, key: \.id)
        async let mealRows: [PlannedMealRecord] = fetchRows("planned_meals", householdID: id, key: \.id)
        async let groceryRefresh: Void = grocerySync.refresh()
        let (hs, m, r, p, _) = try await (householdRows, memberRows, recipeRows, mealRows, groceryRefresh)
        guard !Task.isCancelled, session == syncSession, household?.id == id else { return }
        // Row Level Security hides the household once the owner removes this user.
        guard let h = hs.first, m.contains(where: { $0.userID == userID }) else {
            await leaveRemovedHousehold()
            return
        }
        if pendingWrites == 0, revision == writeRevision {
            household = Household(id: h.id, name: h.name, inviteCode: h.inviteCode)
            // The owner first, then everyone else in the order they joined.
            members = m.sorted { ($0.role == "owner" ? 0 : 1, $0.joinedAt ?? .distantPast) < ($1.role == "owner" ? 0 : 1, $1.joinedAt ?? .distantPast) }
                .map { HouseholdMember(userID: $0.userID, displayName: $0.displayName, role: $0.role, avatarURL: $0.avatarURL.flatMap(URL.init)) }
            recipes = r.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.map(Recipe.init)
            meals = p.compactMap(PlannedMeal.init)
        }
    }

    /// Keyset pagination avoids the Data API's default row cap without increasingly
    /// expensive offsets. Sorting for display happens after all pages are loaded.
    private func fetchRows<Row: Decodable>(_ table: String, householdID: UUID,
                                           idColumn: String = "id", key: KeyPath<Row, UUID>) async throws -> [Row] {
        var rows: [Row] = []
        var cursor: UUID?
        let pageSize = 500
        while true {
            try Task.checkCancellation()
            var query = supabase.from(table).select().eq("household_id", value: householdID)
            if let cursor { query = query.gt(idColumn, value: cursor) }
            let page: [Row] = try await query.order(idColumn).limit(pageSize).execute().value
            rows.append(contentsOf: page)
            guard page.count == pageSize, let last = page.last else { return rows }
            cursor = last[keyPath: key]
        }
    }

    func refresh() async {
        do { try await reload() } catch { report(error) }
    }

    func resumeSync() async {
        guard phase == .ready, !isPreview else { return }
        if channel?.status != .subscribed {
            await startRealtime()
        }
        await refresh()
    }

    private func startRealtime() async {
        guard !realtimeStarting else { return }
        realtimeStarting = true
        defer { realtimeStarting = false }
        let session = syncSession
        await stopRealtime()
        guard session == syncSession, let householdID = household?.id else { return }
        await supabase.realtimeV2.setAuth()
        guard session == syncSession else { return }
        let channel = supabase.channel("household:\(householdID.uuidString.lowercased())") {
            $0.isPrivate = true
        }
        let changes = channel.broadcastStream(event: "CHANGE")
        let statuses = channel.statusChange
        self.channel = channel
        realtimeTask = Task { [weak self] in
            for await payload in changes {
                guard !Task.isCancelled, let self, session == self.syncSession else { return }
                // Broadcast contains only a table name. All data is fetched through
                // RLS; private channel authorization also prevents cross-household events.
                // supabase-swift delivers the Broadcast envelope, with our data
                // nested under "payload", rather than the inner object alone.
                guard let table = payload["payload"]?.objectValue?["table"]?.stringValue else { continue }
                if table == "grocery_items" {
                    self.grocerySync.requestReload()
                } else {
                    self.scheduleReload()
                }
            }
        }
        realtimeStatusTask = Task { [weak self] in
            for await status in statuses {
                guard !Task.isCancelled else { return }
                // Subscribe before fetching: closes the initial-load gap and catches
                // changes missed during a network outage on every successful rejoin.
                if status == .subscribed { await self?.refresh() }
            }
        }
        realtimeConnectionTask = Task { [weak self] in
            var reportedFailure = false
            while !Task.isCancelled {
                if channel.status != .subscribed {
                    do {
                        try await channel.subscribeWithError()
                        reportedFailure = false
                    } catch {
                        guard !Task.isCancelled else { return }
                        if !reportedFailure { self?.report(error); reportedFailure = true }
                    }
                }
                // The SDK reconnects automatically; this also retries if its
                // finite retry budget is exhausted while the tab remains open.
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        realtimeConnectionTask?.cancel()
        realtimeConnectionTask = nil
        realtimeStatusTask?.cancel()
        realtimeStatusTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        grocerySync.cancelReload()
        if let channel { await supabase.removeChannel(channel) }
        channel = nil
    }

    /// Coalesces a burst of change events into one refetch.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: Recipes

    enum PhotoChange {
        case keep, replace(UIImage), remove
    }

    /// Saves a recipe, uploading a new photo first when there is one. The new photo shows right away from the cache.
    func saveRecipe(_ recipe: Recipe, photo: PhotoChange = .keep, onSaved: (() -> Void)? = nil) {
        var recipe = recipe
        let previousPath = recipes.first { $0.id == recipe.id }?.imagePath
        var upload: (path: String, data: Data)?
        switch photo {
        case .keep: break
        case .replace(let image):
            guard let householdID = household?.id, let data = RecipePhotos.uploadData(for: image) else { break }
            let path = "\(householdID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            RecipePhotos.shared.insert(data, for: path)
            recipe.imagePath = path
            upload = (path, data)
        case .remove:
            recipe.imagePath = nil
        }
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        guard let id = household?.id else { return }
        if isPreview { onSaved?(); return }
        let record = recipe.record(household: id)
        let stalePath = previousPath != recipe.imagePath ? previousPath : nil
        save(onSuccess: onSaved) {
            if let upload {
                try await supabase.storage.from(RecipePhotos.bucket)
                    .upload(upload.path, data: upload.data, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
            }
            try Task.checkCancellation()
            try await supabase.from("recipes").upsert(record).execute()
            try Task.checkCancellation()
            if let stalePath {
                _ = try? await supabase.storage.from(RecipePhotos.bucket).remove(paths: [stalePath])
            }
        }
    }

    /// Deleting a recipe also deletes its planned meals through the database's cascading foreign key.
    /// Grocery items are independent and remain on the shopping list.
    func deleteRecipe(_ recipe: Recipe) {
        guard let householdID = household?.id else { return }
        recipes.removeAll { $0.id == recipe.id }
        meals.removeAll { $0.recipeID == recipe.id }
        save {
            try await supabase.from("recipes").delete()
                .eq("id", value: recipe.id)
                .eq("household_id", value: householdID)
                .execute()
            if let path = recipe.imagePath {
                _ = try? await supabase.storage.from(RecipePhotos.bucket).remove(paths: [path])
            }
        }
    }

    func toggleFavorite(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].isFavorite.toggle()
        let favorite = recipes[index].isFavorite
        save {
            try await supabase.from("recipes").update(["is_favorite": favorite]).eq("id", value: recipe.id).execute()
        }
    }

    // MARK: Meal plan

    /// Plans a recipe in a day's slot, replacing whatever was there. Pass `moving` to relocate an existing meal.
    func saveMeal(date: Date, slot: MealSlot, recipe: Recipe, servings: Int, moving: PlannedMeal? = nil) {
        let day = Calendar.current.startOfDay(for: date)
        let replaced = meal(on: day, slot: slot)
        let meal = PlannedMeal(date: day, slot: slot, recipeID: recipe.id, servings: servings)
        meals.removeAll { $0.id == moving?.id || $0.id == replaced?.id }
        meals.append(meal)
        guard let id = household?.id else { return }
        let parameters = SaveMealParameters(meal: meal.record(household: id), movingID: moving?.id)
        save { try await supabase.rpc("save_planned_meal", params: parameters).execute() }
    }

    func removeMeal(_ meal: PlannedMeal) {
        meals.removeAll { $0.id == meal.id }
        save { try await supabase.from("planned_meals").delete().eq("id", value: meal.id).execute() }
    }

    // MARK: Groceries

    func addGrocery(name: String, amount: String = "", source: String = "General") {
        grocerySync.add(name: name, amount: amount, source: source)
    }

    func toggleGrocery(_ item: GroceryItem) { grocerySync.toggle(item.id) }

    func reorderGroceries(_ ordered: [GroceryItem]) { grocerySync.reorder(ordered) }

    func removeGroceries(_ items: [GroceryItem]) { grocerySync.remove(items.map(\.id)) }

    func clearCompletedGroceries() { removeGroceries(groceries.filter(\.isComplete)) }

    func clearAllGroceries() { removeGroceries(groceries) }

    // MARK: Household data

    var isOwner: Bool { currentMember?.role == "owner" }

    /// Owner only. Deletes every recipe, planned meal, and grocery item in one transaction, then their photos.
    /// Members, the household, and its invite code remain.
    func deleteAllHouseholdData() async throws {
        guard !isPreview, let id = household?.id else { return }
        // Let earlier edits land first so none of them recreate data afterward.
        await writeTask?.value
        let photoPaths: [String] = try await supabase
            .rpc("delete_household_data", params: ["target_household": id]).execute().value
        guard household?.id == id else { return }
        recipes = []
        meals = []
        for start in stride(from: 0, to: photoPaths.count, by: 100) {
            let batch = Array(photoPaths[start..<min(start + 100, photoPaths.count)])
            _ = try? await supabase.storage.from(RecipePhotos.bucket).remove(paths: batch)
        }
        await refresh()
    }

    /// Owner only. Removes another member, who loses access to the household right away.
    func removeMember(_ member: HouseholdMember) {
        guard isOwner, member.role != "owner", let householdID = household?.id else { return }
        members.removeAll { $0.userID == member.userID }
        save {
            try await supabase.from("household_members").delete()
                .eq("household_id", value: householdID).eq("user_id", value: member.userID).execute()
        }
    }

    /// Drops the household's data after this user was removed from it, and returns to the join or create screen.
    private func leaveRemovedHousehold() async {
        await resetAccountData()
        phase = .needsHousehold
    }

    // MARK: Saving

    /// Runs a write in the background. On failure, shows the error and refetches so the screen matches the server.
    private func save(onSuccess: (() -> Void)? = nil, _ operation: @escaping () async throws -> Void) {
        guard !isPreview else { return }
        let session = syncSession
        let token = UUID()
        let previous = writeTask
        pendingWrites += 1
        writeRevision &+= 1
        writeTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, session == syncSession else { return }
            defer { savingTasks[token] = nil }
            do {
                try await operation()
                if session == syncSession { onSuccess?() }
            } catch { if session == syncSession { report(error) } }
            guard session == syncSession else { return }
            pendingWrites -= 1
            writeRevision &+= 1
            if pendingWrites == 0 { await refresh() }
        }
        savingTasks[token] = writeTask
    }

    func updateGrocery(_ item: GroceryItem, original: GroceryItem) {
        grocerySync.update(item, original: original)
    }

    func importGroceries(_ items: [GroceryItem]) {
        guard household != nil else { return }
        grocerySync.insert(items)
    }

    /// Fills in the aisle of every unsorted item, including ones another member added.
    /// Whichever device gets there first saves the aisle for the whole household.
    private func sortGroceriesIntoAisles() {
        guard aisleTask == nil, !isPreview, let id = household?.id else { return }
        let session = syncSession
        aisleTask = Task { [weak self] in
            guard let self else { return }
            defer { if session == syncSession { aisleTask = nil } }
            // Repeats for items added or renamed while the previous batch was being sorted.
            while !Task.isCancelled, session == syncSession, household?.id == id {
                let unsorted = groceries.filter { $0.aisle == nil && self.sortedNames[$0.id] != $0.name }
                guard !unsorted.isEmpty else { return }
                let names = Array(Set(unsorted.map(\.name)))
                let aisles = await GroceryAisleClassifier.aisles(for: names)
                guard !Task.isCancelled, session == syncSession, household?.id == id else { return }
                let assigned = grocerySync.assignAisles(aisles.mapValues(\.rawValue))
                for item in assigned { sortedNames[item.id] = item.name }
            }
        }
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        errorMessage = error.localizedDescription
    }
}
