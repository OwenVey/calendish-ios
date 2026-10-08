import SwiftUI
import Observation
import Supabase
import GoogleSignIn
import CryptoKit

/// The signed-in person's household, the recipes available to them, and the household's meal plan and grocery list.
/// Edits apply locally right away, then save to Supabase; changes from other members arrive over Realtime.
@Observable
final class HouseholdStore {
    enum Phase: Equatable {
        case loading, signedOut, onboarding, ready
    }

    /// An invitation opened while signed in, waiting for the person to review the move.
    struct InviteReview: Identifiable {
        let code: String
        var id: String { code }
    }

    private(set) var phase: Phase = .loading
    private(set) var household: Household?
    private(set) var members: [HouseholdMember] = []
    private(set) var userID: UUID?
    /// The person's own recipes, household recipes, and recipes other members share.
    var recipes: [Recipe] = []
    var meals: [PlannedMeal] = []
    var groceries: [GroceryItem] { grocerySync.items }
    var planningDate = Calendar.current.startOfDay(for: Date.now)
    /// The latest failed save or load, shown as an alert.
    var errorMessage: String?
    var needsPasswordReset = false
    /// An invite code opened before onboarding finished. It survives sign-up and relaunching.
    private(set) var pendingInvite = UserDefaults.standard.string(forKey: HouseholdStore.pendingInviteKey)
    var inviteToReview: InviteReview?

    private static let pendingInviteKey = "pendingHouseholdInvite"
    private let client: SupabaseClient
    private let isPreview: Bool
    private var channel: RealtimeChannelV2?
    private var personalChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var reloadTask: Task<Void, Never>?
    private var membershipTask: Task<Void, Never>?
    private var realtimeStarting = false
    private var writeTask: Task<Void, Never>?
    private var savingTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingWrites = 0
    private var writeRevision: UInt64 = 0
    @ObservationIgnored private lazy var grocerySync = GrocerySync(
        transport: isPreview ? nil : SupabaseGroceryTransport(client: client),
        onChange: { [weak self] in self?.sortGroceriesIntoAisles() },
        onError: { [weak self] error in self?.report(error) })
    private var aisleTask: Task<Void, Never>?
    /// The name each item was last sorted under, so a failed save isn't retried on every refetch.
    private var sortedNames: [UUID: String] = [:]
    /// Replaced whenever the account or household changes, so older work can't publish into the new one.
    private var syncSession = UUID()

    init(client: SupabaseClient = supabase) { self.client = client; isPreview = false }

    /// Sample content with no account or network, for SwiftUI previews.
    static func preview() -> HouseholdStore {
        let store = HouseholdStore(previewing: true)
        let today = Calendar.current.startOfDay(for: .now)
        let me = UUID(), partner = UUID()
        var recipes = SampleRecipes.all
        recipes[0].owner = .person(me, shared: true)
        recipes[1].owner = .person(partner, shared: true)
        recipes[2].owner = .household
        recipes[3].owner = .person(me, shared: false)
        store.phase = .ready
        store.userID = me
        store.household = Household(id: UUID(), name: "Our household", inviteCode: "PREVIEW1")
        store.members = [HouseholdMember(userID: me, displayName: "Owen", role: "owner"),
                         HouseholdMember(userID: partner, displayName: "Sam", role: "member")]
        store.recipes = recipes
        store.meals = [
            PlannedMeal(date: today, slot: .breakfast, recipe: recipes[2], recipeID: recipes[2].id, servings: 2),
            PlannedMeal(date: today, slot: .dinner, recipe: recipes[0], recipeID: recipes[0].id, servings: 4),
            PlannedMeal(date: Calendar.current.date(byAdding: .day, value: 1, to: today)!, slot: .dinner, recipe: recipes[1], recipeID: recipes[1].id, servings: 4)
        ]
        store.grocerySync.setHousehold(store.household?.id, items: [
            GroceryItem(name: "Cherry tomatoes", amount: "2 cups", source: "Lemon & herb orzo", position: 0),
            GroceryItem(name: "Orzo", amount: "1½ cups", source: "Lemon & herb orzo", position: 1),
            GroceryItem(name: "Greek yogurt", amount: "1 tub", source: "General", position: 2),
            GroceryItem(name: "Olive oil", amount: "2 tbsp", source: "Lemon & herb orzo", isComplete: true, position: 3)
        ])
        return store
    }

    private init(previewing: Bool) { client = supabase; isPreview = previewing }

    var remainingGroceries: Int { groceries.filter { !$0.isComplete }.count }
    var currentMember: HouseholdMember? { members.first { $0.userID == userID } }
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
        for await (event, session) in client.auth.authStateChanges {
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

    /// Invalidates in-flight reads and writes before awaiting channel teardown.
    @discardableResult
    private func resetHouseholdData() async -> UUID {
        phase = .loading
        let session = UUID()
        syncSession = session
        for task in savingTasks.values { task.cancel() }
        savingTasks.removeAll()
        writeTask?.cancel(); writeTask = nil
        aisleTask?.cancel(); aisleTask = nil
        sortedNames = [:]
        pendingWrites = 0
        writeRevision &+= 1
        grocerySync.setHousehold(nil)
        household = nil
        members = []; recipes = []; meals = []
        await stopRealtime()
        return session
    }

    private func resetAccountData() async {
        await resetHouseholdData()
        needsPasswordReset = false
        inviteToReview = nil
        // Private recipe photos must not survive an account change on this device.
        RecipePhotos.shared.clearCache()
        ProfilePhotos.shared.clearCache()
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

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    /// Returns false when Supabase wants the email confirmed before the first sign-in.
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password)
        return response.session != nil
    }

    func signOut() async {
        do { try await client.auth.signOut() } catch { report(error) }
    }

    /// Finishes onboarding: joins the pending invitation's household, or starts a solo household.
    /// Safe to repeat; the database returns the household the person already has.
    func startHousehold(memberName: String) async throws {
        let session = syncSession
        let row: HouseholdRecord = try await client
            .rpc("start_household", params: StartHouseholdParameters(member_name: memberName, code: pendingInvite))
            .execute().value
        guard session == syncSession else { throw CancellationError() }
        setPendingInvite(nil)
        try await enter(row)
    }

    func discardPendingInvite() { setPendingInvite(nil) }

    private func setPendingInvite(_ code: String?) {
        pendingInvite = code
        UserDefaults.standard.set(code, forKey: Self.pendingInviteKey)
    }

    /// Handles a `calendish://join/<code>` link. Before onboarding finishes, the invitation waits
    /// until the person has an account; afterward, it opens the move review.
    func openInvite(_ url: URL) -> Bool {
        guard let code = HouseholdInvite.code(from: url) else { return false }
        if phase == .ready { inviteToReview = InviteReview(code: code) } else { setPendingInvite(code) }
        return true
    }

    func renameHousehold(to name: String) {
        guard let id = household?.id, !name.isEmpty, name != household?.name else { return }
        household?.name = name
        save { [client] in try await client.from("households").update(["name": name]).eq("id", value: id).execute() }
    }

    func renameMember(to name: String) {
        guard let householdID = household?.id, let userID, !name.isEmpty, name != currentMember?.displayName,
              let index = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[index].displayName = name
        save { [client] in
            try await client.from("household_members").update(["display_name": name])
                .eq("household_id", value: householdID).eq("user_id", value: userID).execute()
        }
    }

    /// The name given at sign-up, or the first name from Google.
    var suggestedDisplayName: String {
        guard !isPreview, let metadata = client.auth.currentUser?.userMetadata else { return "" }
        if case let .string(name)? = metadata["display_name"], !name.isEmpty { return name }
        if case let .string(name)? = metadata["full_name"] ?? metadata["name"] {
            return name.components(separatedBy: " ").first ?? name
        }
        return ""
    }

    /// The email on the signed-in account, if it has one.
    var accountEmail: String? {
        guard !isPreview else { return "owen@example.com" }
        return client.auth.currentUser?.email
    }

    private func loadHousehold() async {
        let session = syncSession
        phase = .loading
        do {
            let fetched = try await fetchCurrentHousehold()
            guard session == syncSession else { return }
            guard let row = fetched else {
                phase = .onboarding
                return
            }
            try await enter(row)
        } catch {
            guard session == syncSession, !(error is CancellationError) else { return }
            report(error)
            // Onboarding is repeatable, so it finds an existing household rather than creating another.
            phase = .onboarding
        }
    }

    /// The person's one household, according to the server.
    private func fetchCurrentHousehold() async throws -> HouseholdRecord? {
        guard let userID else { return nil }
        let memberships: [MemberRecord] = try await client.from("household_members")
            .select().eq("user_id", value: userID).execute().value
        guard let householdID = memberships.first?.householdID else { return nil }
        return try await client.from("households").select().eq("id", value: householdID).single().execute().value
    }

    func updatePassword(_ password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
        needsPasswordReset = false
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "calendish://login-callback"))
    }

    private func enter(_ row: HouseholdRecord) async throws {
        let session = syncSession
        household = Household(id: row.id, name: row.name, inviteCode: row.inviteCode)
        grocerySync.setHousehold(row.id)
        try await reload()
        guard session == syncSession else { throw CancellationError() }
        phase = .ready
        syncAvatar()
        // An invitation opened before signing in to an account that already had a household.
        if let pendingInvite {
            inviteToReview = InviteReview(code: pendingInvite)
            setPendingInvite(nil)
        }
        await startRealtime()
    }

    /// Leaves the current household's data and subscriptions behind and opens another household.
    private func switchHousehold(to row: HouseholdRecord) async {
        guard row.id != household?.id else {
            await refresh()
            return
        }
        let person = userID
        let session = await resetHouseholdData()
        guard person == userID, session == syncSession else { return }
        do { try await enter(row) } catch {
            guard session == syncSession, !(error is CancellationError) else { return }
            report(error)
            await loadHousehold()
        }
    }

    /// Copies the Google profile photo onto this member's row so the rest of the household can see it.
    private func syncAvatar() {
        guard let householdID = household?.id, let userID,
              case let .string(avatar)? = client.auth.currentUser?.userMetadata["avatar_url"] ?? client.auth.currentUser?.userMetadata["picture"],
              let url = URL(string: avatar), currentMember?.avatarURL == nil,
              let index = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[index].avatarURL = url
        save { [client] in
            try await client.from("household_members").update(["avatar_url": avatar])
                .eq("household_id", value: householdID).eq("user_id", value: userID).execute()
        }
    }

    /// Commit the member row only after uploading. A sentinel reference records explicit removal,
    /// so Google cannot restore a photo the person chose to remove. Household moves preserve it.
    func setProfilePhoto(_ image: UIImage?) async throws {
        guard let householdID = household?.id, let userID else { throw CancellationError() }
        let session = syncSession
        let oldURL = currentMember?.avatarURL
        var newURL = ProfilePhotos.removedReference
        var uploadedPath: String?
        if let image {
            guard let data = image.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
            let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            newURL = ProfilePhotos.reference(path: path)
            if !isPreview {
                try await client.storage.from(ProfilePhotos.bucket).upload(path, data: data, options: .init(cacheControl: "0", contentType: "image/jpeg"))
                uploadedPath = path
            }
            ProfilePhotos.shared.insert(image, for: newURL)
        }
        var memberWriteStarted = false
        do {
            guard session == syncSession else { throw CancellationError() }
            if !isPreview {
                memberWriteStarted = true
                let rows: [MemberRecord] = try await client.from("household_members")
                    .update(["avatar_url": newURL.absoluteString])
                    .eq("household_id", value: householdID).eq("user_id", value: userID)
                    .select().execute().value
                guard rows.count == 1 else { throw CocoaError(.fileWriteNoPermission) }
            }
        } catch {
            // A lost response can follow a successful commit. Never delete a photo that the
            // member row might now reference; confirm the result before rolling back Storage.
            let rows: [MemberRecord]? = memberWriteStarted && session == syncSession
                ? try? await client.from("household_members").select()
                    .eq("household_id", value: householdID).eq("user_id", value: userID).execute().value
                : nil
            if rows?.first?.avatarURL != newURL.absoluteString {
                if let uploadedPath, !memberWriteStarted || rows != nil {
                    _ = try? await client.storage.from(ProfilePhotos.bucket).remove(paths: [uploadedPath])
                }
                throw error
            }
        }
        if session == syncSession, let index = members.firstIndex(where: { $0.userID == userID }) {
            members[index].avatarURL = newURL
        }
        if !isPreview, let oldPath = ProfilePhotos.path(for: oldURL) {
            _ = try? await client.storage.from(ProfilePhotos.bucket).remove(paths: [oldPath])
        }
    }

    // MARK: Household moves

    var isOwner: Bool { currentMember?.role == "owner" }

    /// What joining with `code`, or leaving when `code` is nil, would do. Changes nothing.
    func previewMove(code: String?) async throws -> HouseholdMovePreview {
        if isPreview {
            return HouseholdMovePreview(destination: code == nil ? nil : .init(id: UUID(), name: "Sam’s household", members: ["Sam"]),
                currentHouseholdID: household?.id, currentHouseholdName: household?.name, isCurrent: false,
                otherMembers: members.count - 1,
                successor: isOwner ? members.first(where: { $0.userID != userID }).map { .init(userID: $0.userID, displayName: $0.displayName) } : nil,
                deletesHousehold: members.count == 1, personalRecipes: recipes.filter(isMine).count,
                sharedRecipes: recipes.filter { isMine($0) && $0.owner?.isShared == true }.count,
                householdRecipes: recipes.filter { $0.owner == .household }.count, plannedMeals: meals.count, groceries: groceries.count)
        }
        return         try await client.rpc("preview_household_move", params: PreviewMoveParameters(code: code.map(HouseholdInvite.normalized)))
            .execute().value
    }

    /// Joins the invited household in place of the current one, as confirmed in `preview`.
    func joinHousehold(code: String, confirmed preview: HouseholdMovePreview, saveHouseholdRecipes: Bool) async throws {
        let parameters = JoinHouseholdParameters(code: HouseholdInvite.normalized(code), save_household_recipes: saveHouseholdRecipes,
                                                 expected_household: preview.currentHouseholdID)
        try await move(from: preview) { try await client.rpc("join_household", params: parameters).execute().value }
    }

    /// Leaves for a fresh solo household, as confirmed in `preview`.
    func leaveHousehold(confirmed preview: HouseholdMovePreview, saveHouseholdRecipes: Bool) async throws {
        let parameters = LeaveHouseholdParameters(save_household_recipes: saveHouseholdRecipes, expected_household: preview.currentHouseholdID)
        try await move(from: preview) { try await client.rpc("leave_household", params: parameters).execute().value }
    }

    /// Runs a membership change on the server, then opens the resulting household. If the response is lost,
    /// the server's membership decides whether the move happened rather than assuming either way.
    private func move(from preview: HouseholdMovePreview, _ operation: () async throws -> HouseholdMoveResult) async throws {
        guard !isPreview else { return }
        // Let earlier edits land in the household they were made for.
        let session = syncSession
        await writeTask?.value
        guard session == syncSession else { throw CancellationError() }
        let result: HouseholdMoveResult
        do {
            result = try await operation()
        } catch {
            guard session == syncSession else { throw CancellationError() }
            guard !(error is PostgrestError), let row = try? await fetchCurrentHousehold(),
                  row.id != preview.currentHouseholdID else { throw error }
            guard session == syncSession else { throw CancellationError() }
            await switchHousehold(to: row)
            return
        }
        guard session == syncSession else { throw CancellationError() }
        await switchHousehold(to: result.household)
        await removePhotos(result.unusedPhotos)
    }

    /// Owner only. The new owner manages membership; the previous owner stays as a member.
    func transferOwnership(to member: HouseholdMember) {
        guard isOwner, member.userID != userID, let householdID = household?.id else { return }
        for index in members.indices {
            members[index].role = members[index].userID == member.userID ? "owner" : "member"
        }
        save { [client] in
            try await client.rpc("transfer_household_ownership",
                                   params: TransferOwnershipParameters(target_household: householdID, new_owner: member.userID)).execute()
        }
    }

    /// Owner only. Removes another member, who keeps their personal recipes and gets a solo household.
    /// Their shared recipes stay as household copies, and the invite code changes so they can't rejoin with it.
    func removeMember(_ member: HouseholdMember) {
        guard isOwner, member.role != "owner", let householdID = household?.id else { return }
        members.removeAll { $0.userID == member.userID }
        save { [client] in
            try await client.rpc("remove_household_member",
                                   params: ["target_household": householdID, "target_user": member.userID]).execute()
        }
    }

    /// Follows a membership change made elsewhere, such as removal or a move on another device.
    private func checkMembership() {
        guard membershipTask == nil, !isPreview else { return }
        // Not tied to Realtime tasks, which a household switch cancels.
        membershipTask = Task { [weak self] in
            guard let self else { return }
            defer { membershipTask = nil }
            let session = syncSession
            let row: HouseholdRecord?
            do { row = try await fetchCurrentHousehold() } catch { return }
            guard session == syncSession, phase == .ready else { return }
            if let row {
                if row.id != household?.id { await switchHousehold(to: row) }
            } else {
                let resetSession = await resetHouseholdData()
                guard resetSession == syncSession else { return }
                phase = .onboarding
            }
        }
    }

    // MARK: Loading

    /// Fetches everything for the household. The data set is small enough to refetch whole.
    func reload() async throws {
        guard !isPreview, let id = household?.id else { return }
        let session = syncSession
        let revision = writeRevision
        async let householdRows: [HouseholdRecord] = client.from("households").select().eq("id", value: id).execute().value
        async let memberRows: [MemberRecord] = fetchRows("household_members", householdID: id, idColumn: "user_id", key: \.userID)
        // Row Level Security limits this to the person's recipes, household recipes, and members' shared recipes.
        async let recipeRows: [RecipeRecord] = fetchRows("recipes", key: \.id)
        async let favoriteRows: [FavoriteRecord] = fetchRows("recipe_favorites", idColumn: "recipe_id", key: \.recipeID)
        async let mealRows: [PlannedMealRecord] = fetchRows("planned_meals", householdID: id, key: \.id)
        async let groceryRefresh: Void = grocerySync.refresh()
        let (hs, m, r, f, p, _) = try await (householdRows, memberRows, recipeRows, favoriteRows, mealRows, groceryRefresh)
        guard !Task.isCancelled, session == syncSession, household?.id == id else { return }
        // Row Level Security hides the household once this person is removed or moves elsewhere.
        guard let h = hs.first, m.contains(where: { $0.userID == userID }) else {
            checkMembership()
            return
        }
        if pendingWrites == 0, revision == writeRevision {
            household = Household(id: h.id, name: h.name, inviteCode: h.inviteCode)
            // The owner first, then everyone else in the order they joined.
            members = m.sorted { ($0.role == "owner" ? 0 : 1, $0.joinedAt ?? .distantPast) < ($1.role == "owner" ? 0 : 1, $1.joinedAt ?? .distantPast) }
                .map { HouseholdMember(userID: $0.userID, displayName: $0.displayName, role: $0.role, avatarURL: $0.avatarURL.flatMap(URL.init)) }
            let favorites = Set(f.map(\.recipeID))
            recipes = r.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.map { Recipe($0, favorites: favorites) }
            meals = p.compactMap(PlannedMeal.init)
        }
    }

    /// Keyset pagination avoids the Data API's default row cap without increasingly
    /// expensive offsets. Sorting for display happens after all pages are loaded.
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

    func refresh() async {
        do { try await reload() } catch { report(error) }
    }

    func resumeSync() async {
        guard phase == .ready, !isPreview else { return }
        if channel?.status != .subscribed || personalChannel?.status != .subscribed {
            await startRealtime()
        }
        await refresh()
    }

    /// Listens on the household's topic for shared changes and on the person's own topic
    /// for their membership, favorites, and personal recipes.
    private func startRealtime() async {
        guard !realtimeStarting else { return }
        realtimeStarting = true
        defer { realtimeStarting = false }
        let session = syncSession
        await stopRealtime()
        guard session == syncSession, let householdID = household?.id, let userID else { return }
        await client.realtimeV2.setAuth()
        guard session == syncSession else { return }
        let channel = client.channel("household:\(householdID.uuidString.lowercased())") { $0.isPrivate = true }
        let personalChannel = client.channel("user:\(userID.uuidString.lowercased())") { $0.isPrivate = true }
        self.channel = channel
        self.personalChannel = personalChannel
        for subscribed in [channel, personalChannel] {
            let changes = subscribed.broadcastStream(event: "CHANGE")
            let statuses = subscribed.statusChange
            realtimeTasks.append(Task { [weak self] in
                for await payload in changes {
                    guard !Task.isCancelled, let self, session == self.syncSession else { return }
                    // Broadcast contains only a table name. All data is fetched through
                    // RLS; private channel authorization also prevents cross-household events.
                    // supabase-swift delivers the Broadcast envelope, with our data
                    // nested under "payload", rather than the inner object alone.
                    guard let table = payload["payload"]?.objectValue?["table"]?.stringValue else { continue }
                    switch table {
                    case "grocery_items": self.grocerySync.requestReload()
                    case "household_members" where subscribed === personalChannel: self.checkMembership()
                    default: self.scheduleReload()
                    }
                }
            })
            realtimeTasks.append(Task { [weak self] in
                for await status in statuses {
                    guard !Task.isCancelled else { return }
                    // Subscribe before fetching: closes the initial-load gap and catches
                    // changes missed during a network outage on every successful rejoin.
                    guard status == .subscribed else { continue }
                    if subscribed === personalChannel { self?.checkMembership() } else { await self?.refresh() }
                }
            })
        }
        realtimeTasks.append(Task { [weak self] in
            var reportedFailure = false
            while !Task.isCancelled {
                for subscribed in [channel, personalChannel] where subscribed.status != .subscribed {
                    do {
                        try await subscribed.subscribeWithError()
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
        })
    }

    private func stopRealtime() async {
        for task in realtimeTasks { task.cancel() }
        realtimeTasks = []
        reloadTask?.cancel()
        reloadTask = nil
        grocerySync.cancelReload()
        let previousChannel = channel
        let previousPersonalChannel = personalChannel
        channel = nil
        personalChannel = nil
        if let previousChannel { await client.removeChannel(previousChannel) }
        if let previousPersonalChannel { await client.removeChannel(previousPersonalChannel) }
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

    var hasOtherMembers: Bool { members.count > 1 }

    /// Owners edit their personal originals; every member edits household recipes.
    func canEdit(_ recipe: Recipe) -> Bool {
        switch recipe.owner {
        case .person(let owner, _)?: owner == userID
        case .household?: true
        case nil: false
        }
    }

    func isMine(_ recipe: Recipe) -> Bool { recipe.owner?.person == userID && userID != nil }

    /// "You", the owning member's name, or "Household".
    func ownerName(of recipe: Recipe) -> String? {
        switch recipe.owner {
        case .person(let owner, _)?:
            owner == userID ? "You" : members.first { $0.userID == owner }?.displayName ?? "Another member"
        case .household?: "Household"
        case nil: nil
        }
    }

    /// Saves a recipe, uploading a new photo first when there is one. The new photo shows right away from the cache.
    /// A new recipe is the person's own; set its owner to `.person(_, shared: false)` to keep it Only Me.
    func saveRecipe(_ recipe: Recipe, photo: PhotoChange = .keep, onSaved: (() -> Void)? = nil) {
        guard let userID else { return }
        var recipe = recipe
        let existing = recipes.first { $0.id == recipe.id }
        if existing == nil { recipe.owner = .person(userID, shared: recipe.owner?.isShared ?? true) }
        let previousPath = existing?.imagePath
        var upload: (path: String, data: Data)?
        switch photo {
        case .keep: break
        case .replace(let image):
            // Household recipe photos live with the household; personal ones with their owner.
            guard let folder = recipe.owner == .household ? household?.id : userID,
                  let data = RecipePhotos.uploadData(for: image) else { break }
            let path = "\(folder.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
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
        if isPreview { onSaved?(); return }
        let saved = recipe
        let stalePath = previousPath != recipe.imagePath ? previousPath : nil
        save(onSuccess: onSaved) { [client, weak self] in
            if let upload {
                try await client.storage.from(RecipePhotos.bucket)
                    .upload(upload.path, data: upload.data, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
            }
            try Task.checkCancellation()
            if existing == nil {
                try await client.from("recipes")
                    .insert(NewRecipeRecord(id: saved.id, ownerID: userID, isShared: saved.owner?.isShared ?? true, content: saved.content))
                    .execute()
            } else {
                try await client.from("recipes").update(saved.content).eq("id", value: saved.id).execute()
            }
            try Task.checkCancellation()
            // Storage keeps a photo that a copy or planned meal still uses.
            if let stalePath { await self?.removePhotos([stalePath]) }
        }
    }

    func deletionExplanation(for recipe: Recipe) -> String {
        let retained = isMine(recipe) && recipe.owner?.isShared == true ? " Your household keeps an independent copy of your shared recipe." : ""
        return "This permanently deletes this recipe. Planned meals keep their saved versions and groceries stay unchanged." + retained
    }

    /// Owners delete their originals, and members delete household recipes. Deleting a shared original
    /// leaves the household a copy. Planned meals keep their saved versions, and groceries stay.
    func deleteRecipe(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        for index in meals.indices where meals[index].recipeID == recipe.id { meals[index].recipeID = nil }
        save { [client, weak self] in
            let unused: [String] = try await client.rpc("delete_recipe", params: ["target_recipe": recipe.id]).execute().value
            await self?.removePhotos(unused)
        }
    }

    /// Owner only. Ending sharing leaves the household its own copy; it doesn't retract what was shared.
    func setSharing(_ recipe: Recipe, shared: Bool) {
        guard isMine(recipe), let userID, let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].owner = .person(userID, shared: shared)
        save { [client] in
            try await client.rpc("set_recipe_sharing", params: RecipeSharingParameters(target_recipe: recipe.id, shared: shared)).execute()
        }
    }

    /// Saves a private copy of another member's or the household's recipe into the person's collection.
    @discardableResult
    func saveCopy(of recipe: Recipe) async throws -> Recipe {
        guard !isPreview, userID != nil else {
            var copy = recipe
            copy.id = UUID()
            copy.owner = .person(userID ?? UUID(), shared: false)
            recipes.insert(copy, at: 0)
            return copy
        }
        let session = syncSession
        let person = userID
        let row: RecipeRecord = try await client.rpc("save_recipe_copy", params: ["source_recipe": recipe.id]).execute().value
        guard session == syncSession, person == userID else { throw CancellationError() }
        let copy = Recipe(row)
        if !recipes.contains(where: { $0.id == copy.id }) { recipes.insert(copy, at: 0) }
        return copy
    }

    /// Favorites are personal, so starring a recipe doesn't change anyone else's list.
    func toggleFavorite(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }), let userID else { return }
        recipes[index].isFavorite.toggle()
        let favorite = recipes[index].isFavorite
        save { [client] in
            if favorite {
                try await client.from("recipe_favorites")
                    .upsert(FavoriteRecord(recipeID: recipe.id), onConflict: "user_id,recipe_id", returning: .minimal, ignoreDuplicates: true)
                    .execute()
            } else {
                try await client.from("recipe_favorites").delete()
                    .eq("user_id", value: userID).eq("recipe_id", value: recipe.id).execute()
            }
        }
    }

    /// Storage can't be cleaned up from SQL; the database reports photos nothing uses anymore.
    private func removePhotos(_ paths: [String]) async {
        for start in stride(from: 0, to: paths.count, by: 100) {
            let batch = Array(paths[start..<min(start + 100, paths.count)])
            _ = try? await client.storage.from(RecipePhotos.bucket).remove(paths: batch)
        }
    }

    // MARK: Meal plan

    /// The source recipe as it is now, while it still exists and is available.
    func latestRecipe(for meal: PlannedMeal) -> Recipe? {
        meal.recipeID.flatMap { id in recipes.first { $0.id == id } }
    }

    func hasNewerVersion(_ meal: PlannedMeal) -> Bool {
        latestRecipe(for: meal).map { !$0.hasSameVersion(as: meal.recipe) } ?? false
    }

    /// Plans a recipe in a day's slot, replacing whatever was there, and saves its current version.
    /// Pass `moving` to relocate an existing meal; with `keepVersion`, it keeps its saved recipe version.
    func saveMeal(date: Date, slot: MealSlot, recipe: Recipe, servings: Int, moving: PlannedMeal? = nil, keepVersion: Bool = false) {
        let day = Calendar.current.startOfDay(for: date)
        let replaced = meal(on: day, slot: slot)
        let kept = keepVersion ? moving : nil
        let meal = PlannedMeal(date: day, slot: slot, recipe: kept?.recipe ?? recipe,
                               recipeID: kept != nil ? kept?.recipeID : recipe.id, servings: servings)
        meals.removeAll { $0.id == moving?.id || $0.id == replaced?.id }
        meals.append(meal)
        guard let id = household?.id else { return }
        let parameters = SaveMealParameters(target_household: id, meal_id: meal.id, meal_date: DayFormat.string(from: day),
                                            meal_slot: slot.rawValue, meal_recipe: kept == nil ? recipe.id : nil,
                                            meal_servings: servings, moving_id: moving?.id, keep_version: kept != nil)
        save { [client] in try await client.rpc("save_planned_meal", params: parameters).execute() }
    }

    /// Replaces a planned meal's saved version with its recipe's latest. Groceries already added stay as they are.
    func updateMealToLatest(_ meal: PlannedMeal) {
        guard let latest = latestRecipe(for: meal), let index = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        meals[index] = PlannedMeal(id: meal.id, date: meal.date, slot: meal.slot, recipe: latest, recipeID: latest.id, servings: meal.servings)
        save { [client] in try await client.rpc("update_planned_meal_to_latest", params: ["target_meal": meal.id]).execute() }
    }

    func removeMeal(_ meal: PlannedMeal) {
        meals.removeAll { $0.id == meal.id }
        save { [client] in try await client.from("planned_meals").delete().eq("id", value: meal.id).execute() }
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

    /// Owner only. Deletes household recipes, planned meals, and grocery items in one transaction, then
    /// photos nothing uses anymore. Members, their personal recipes, the household, and its invite code remain.
    func deleteAllHouseholdData() async throws {
        guard !isPreview, let id = household?.id else { return }
        // Let earlier edits land first so none of them recreate data afterward.
        await writeTask?.value
        let photoPaths: [String] = try await client
            .rpc("delete_household_data", params: ["target_household": id]).execute().value
        guard household?.id == id else { return }
        recipes.removeAll { $0.owner == .household }
        meals = []
        await removePhotos(photoPaths)
        await refresh()
    }

    // MARK: Account

    /// Deletes the account and personal recipes. The household keeps copies of shared recipes and passes
    /// ownership on, or is deleted when nobody else remains. Then signs out on this device.
    func deleteAccount() async throws {
        guard !isPreview, let userID else { return }
        let session = syncSession
        await writeTask?.value
        guard session == syncSession else { throw CancellationError() }
        let photoPaths: [String] = try await client.rpc("delete_account").execute().value
        // The session's token stays valid until it expires, which is long enough to clean up Storage.
        await removePhotos(photoPaths)
        let folder = userID.uuidString.lowercased()
        if let avatars = try? await client.storage.from(ProfilePhotos.bucket).list(path: folder), !avatars.isEmpty {
            _ = try? await client.storage.from(ProfilePhotos.bucket).remove(paths: avatars.map { "\(folder)/\($0.name)" })
        }
        // The server session no longer exists, so only clear this device's.
        try? await client.auth.signOut(scope: .local)
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
