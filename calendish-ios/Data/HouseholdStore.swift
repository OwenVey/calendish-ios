import SwiftUI
import Observation

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
    var notes: [MealPlanNote] = []
    /// Each member's ratings and notes on recipes this person can see, including their own.
    var reviews: [RecipeReview] = []
    /// Days the household marked recipes as cooked.
    var cooks: [RecipeCook] = []
    /// The latest failed save or load, shown as an alert.
    var errorMessage: String?
    var errorTitle = "Couldn’t update household data"
    var needsPasswordReset = false
    /// An invite code opened before onboarding finished. It survives sign-up and relaunching.
    private(set) var pendingInvite = UserDefaults.standard.string(forKey: HouseholdStore.pendingInviteKey)
    var inviteToReview: InviteReview?

    private static let pendingInviteKey = "pendingHouseholdInvite"
    private let backend: any HouseholdBackend
    private let finishedCooks: FinishedCooks
    private var subscription: (any HouseholdSubscription)?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var reloadTask: Task<Void, Never>?
    private var membershipTask: Task<Void, Never>?
    private var realtimeStarting = false
    private var writeTask: Task<Void, Never>?
    private var savingTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingWrites = 0
    private var writeRevision: UInt64 = 0
    @ObservationIgnored private(set) lazy var groceries = GrocerySync(
        transport: backend.groceryTransport,
        onError: { [weak self] error in self?.report(error, action: "update groceries", recovery: "Reopen the list to try again.") },
        defaults: .standard,
        autoClearInterval: { [weak self] in self?.household?.groceryAutoClear.interval },
        classifyAisles: backend.aisleClassifier)
    /// Replaced whenever the account or household changes, so older work can't publish into the new one.
    private var syncSession = UUID()

    init(backend: (any HouseholdBackend)? = nil, finishedCooks: FinishedCooks = .shared) {
        self.backend = backend ?? SupabaseHouseholdBackend()
        self.finishedCooks = finishedCooks
    }

    /// Sample content with no account or network, for SwiftUI previews.
    static func preview() -> HouseholdStore {
        let memory = InMemoryHouseholdBackend()
        let store = HouseholdStore(backend: memory)
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
            PlannedMeal(date: today, recipe: recipes[2], recipeID: recipes[2].id, servings: 2),
            PlannedMeal(date: today, recipe: recipes[0], recipeID: recipes[0].id, servings: 4),
            PlannedMeal(date: Calendar.current.date(byAdding: .day, value: 1, to: today)!, recipe: recipes[1], recipeID: recipes[1].id, servings: 4)
        ]
        store.notes = [MealPlanNote(date: Calendar.current.date(byAdding: .day, value: 2, to: today)!, text: "Leftovers", items: ["Baguette"])]
        store.reviews = [
            RecipeReview(userID: me, recipeID: recipes[0].id, rating: 5, note: "Use half the salt."),
            RecipeReview(userID: partner, recipeID: recipes[0].id, rating: 4, note: "Great with feta on top."),
            RecipeReview(userID: partner, recipeID: recipes[1].id, rating: 5)
        ]
        store.cooks = [
            RecipeCook(recipeID: recipes[0].id, date: Calendar.current.date(byAdding: .day, value: -21, to: today)!, cookedBy: me),
            RecipeCook(recipeID: recipes[1].id, date: Calendar.current.date(byAdding: .day, value: -45, to: today)!, cookedBy: partner)
        ]
        store.groceries.setHousehold(store.household?.id, items: [
            GroceryItem(name: "Cherry tomatoes", amount: "2 cups", source: "Lemon & herb orzo", position: 0),
            GroceryItem(name: "Orzo", amount: "1½ cups", source: "Lemon & herb orzo", position: 1),
            GroceryItem(name: "Greek yogurt", amount: "1 tub", source: "General", position: 2),
            GroceryItem(name: "Olive oil", amount: "2 tbsp", source: "Lemon & herb orzo", isComplete: true, position: 3)
        ])
        memory.account = HouseholdAccount(id: me, email: "owen@example.com")
        memory.seed(HouseholdSnapshot(household: store.household, members: store.members, recipes: store.recipes,
            meals: store.meals, notes: store.notes, reviews: store.reviews, cooks: store.cooks), groceries: store.groceries.items)
        memory.seed(HouseholdSnapshot(household: Household(id: UUID(), name: "Sam’s household", inviteCode: "VALID123"),
            members: [HouseholdMember(userID: UUID(), displayName: "Sam", role: "owner")]))
        return store
    }

    var currentMember: HouseholdMember? { members.first { $0.userID == userID } }
    /// Every tag in the recipe book, sorted, with tags that differ only by case folded together.
    var recipeTags: [String] {
        var seen = Set<String>()
        return recipes.flatMap(\.tags).filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    /// A day's meals, in the order they were planned.
    func meals(on date: Date) -> [PlannedMeal] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: Session

    /// Follows sign-in state for the life of the app.
    func start() async {
        for await change in backend.authChanges {
            guard !Task.isCancelled else { return }
            if let account = change.account {
                CookingSession.shared.setAccount(account.id)
                if userID != account.id {
                    await resetAccountData()
                    userID = account.id
                    await loadHousehold()
                }
                if change.passwordRecovery { needsPasswordReset = true }
            } else {
                CookingSession.shared.setAccount(nil)
                await resetAccountData()
                userID = nil
                phase = .signedOut
            }
        }
    }

    /// Invalidates in-flight reads and writes before awaiting channel teardown.
    @discardableResult
    private func resetHouseholdData() async -> UUID {
        phase = .loading
        finishedCooks.stopRecording()
        let session = UUID()
        syncSession = session
        for task in savingTasks.values { task.cancel() }
        savingTasks.removeAll()
        writeTask?.cancel(); writeTask = nil
        pendingWrites = 0
        writeRevision &+= 1
        groceries.setHousehold(nil)
        household = nil
        members = []; recipes = []; meals = []; notes = []; reviews = []; cooks = []
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
    func signInWithGoogle() async throws { _ = try await backend.authenticate(.google) }

    func signIn(email: String, password: String) async throws { _ = try await backend.authenticate(.email(email, password: password)) }

    /// Returns false when email confirmation is needed before the first sign-in.
    func signUp(email: String, password: String) async throws -> Bool {
        try await backend.authenticate(.signUp(email, password: password))
    }

    func signOut() async {
        do { try await backend.signOut() } catch { report(error, action: "sign out", recovery: "Try signing out again.") }
    }

    /// Finishes onboarding: joins the pending invitation's household, or starts a solo household.
    /// Safe to repeat; the database returns the household the person already has.
    func startHousehold(memberName: String) async throws {
        let session = syncSession
        let row = try await backend.startHousehold(name: memberName, code: pendingInvite)
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
        save(.renameHousehold(id, name))
    }

    /// Applies to every member's list, since clearing deletes the items for everyone.
    func setGroceryAutoClear(_ setting: GroceryAutoClear) {
        guard let id = household?.id, setting != household?.groceryAutoClear else { return }
        household?.groceryAutoClear = setting
        save(.groceryAutoClear(id, setting))
        groceries.clearExpired()
    }

    /// Auto-clear used to be chosen per device. Carry an existing choice over once, unless the household already has one.
    private func adoptDeviceGroceryAutoClear() {
        let key = "groceryAutoClear"
        guard let saved = UserDefaults.standard.string(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        if household?.groceryAutoClear == .never, let setting = GroceryAutoClear(rawValue: saved) { setGroceryAutoClear(setting) }
    }

    func renameMember(to name: String) {
        guard let householdID = household?.id, let userID, !name.isEmpty, name != currentMember?.displayName,
              let index = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[index].displayName = name
        save(.renameMember(household: householdID, user: userID, name: name))
    }

    var suggestedDisplayName: String { backend.account?.displayName ?? "" }
    var accountEmail: String? { backend.account?.email }

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
        return try await backend.currentHousehold(user: userID)
    }

    func updatePassword(_ password: String) async throws {
        _ = try await backend.authenticate(.password(password))
        needsPasswordReset = false
    }

    func resetPassword(email: String) async throws { _ = try await backend.authenticate(.passwordReset(email)) }

    private func enter(_ row: HouseholdRecord) async throws {
        let session = syncSession
        household = row.household
        groceries.setHousehold(row.id)
        try await reload()
        guard session == syncSession else { throw CancellationError() }
        adoptDeviceGroceryAutoClear()
        phase = .ready
        if let userID {
            finishedCooks.record(for: userID) { [weak self] cook, acknowledge in
                guard let self else { acknowledge(false); return }
                self.recordFinishedCook(cook, acknowledge: acknowledge)
            }
        }
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
              let url = backend.account?.avatarURL, currentMember?.avatarURL == nil,
              let index = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[index].avatarURL = url
        save(.avatar(household: householdID, user: userID, url: url))
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
            try await backend.uploadPhoto(.init(path: path, data: data), bucket: .profile)
            uploadedPath = path
            ProfilePhotos.shared.insert(image, for: newURL)
        }
        var memberWriteStarted = false
        do {
            guard session == syncSession else { throw CancellationError() }
            memberWriteStarted = true
            try await backend.write(.avatar(household: householdID, user: userID, url: newURL))
        } catch {
            // A lost response can follow a successful commit. Never delete a photo that the
            // member row might now reference; confirm the result before rolling back Storage.
            var confirmed = false
            var checked = false
            if memberWriteStarted, session == syncSession {
                do { confirmed = try await backend.avatar(household: householdID, user: userID) == newURL; checked = true }
                catch { }
            }
            if !confirmed {
                if let uploadedPath, !memberWriteStarted || checked {
                    await backend.removePhotos([uploadedPath], bucket: .profile)
                }
                throw error
            }
        }
        if session == syncSession, let index = members.firstIndex(where: { $0.userID == userID }) {
            members[index].avatarURL = newURL
        }
        if let oldPath = ProfilePhotos.path(for: oldURL) {
            await backend.removePhotos([oldPath], bucket: .profile)
        }
    }

    // MARK: Household moves

    var isOwner: Bool { currentMember?.role == "owner" }

    /// What joining with `code`, or leaving when `code` is nil, would do. Changes nothing.
    func previewMove(code: String?) async throws -> HouseholdMovePreview {
        try await backend.previewMove(code: code.map(HouseholdInvite.normalized))
    }

    func joinHousehold(code: String, confirmed preview: HouseholdMovePreview, saveHouseholdRecipes: Bool) async throws {
        try await move(from: preview) { [backend] in
            try await backend.move(code: HouseholdInvite.normalized(code), saveRecipes: saveHouseholdRecipes, expected: preview.currentHouseholdID)
        }
    }

    func leaveHousehold(confirmed preview: HouseholdMovePreview, saveHouseholdRecipes: Bool) async throws {
        try await move(from: preview) { [backend] in
            try await backend.move(code: nil, saveRecipes: saveHouseholdRecipes, expected: preview.currentHouseholdID)
        }
    }

    /// Runs a membership change on the server, then opens the resulting household. If the response is lost,
    /// the server's membership decides whether the move happened rather than assuming either way.
    private func move(from preview: HouseholdMovePreview, _ operation: () async throws -> HouseholdMoveResult) async throws {
        // Let earlier edits land in the household they were made for.
        let session = syncSession
        await waitForSaves()
        guard session == syncSession else { throw CancellationError() }
        let result: HouseholdMoveResult
        do {
            result = try await operation()
        } catch {
            guard session == syncSession else { throw CancellationError() }
            guard !(error is HouseholdMoveRejected), let row = try? await fetchCurrentHousehold(),
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
        save(.transferOwnership(household: householdID, user: member.userID))
    }

    /// Owner only. Removes another member, who keeps their personal recipes and gets a solo household.
    /// Their shared recipes stay as household copies, and the invite code changes so they can't rejoin with it.
    func removeMember(_ member: HouseholdMember) {
        guard isOwner, member.role != "owner", let householdID = household?.id else { return }
        members.removeAll { $0.userID == member.userID }
        save(.removeMember(household: householdID, user: member.userID))
    }

    /// Follows a membership change made elsewhere, such as removal or a move on another device.
    private func checkMembership() {
        guard membershipTask == nil else { return }
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
        guard let id = household?.id else { return }
        let session = syncSession
        let revision = writeRevision
        async let snapshot = backend.snapshot(household: id)
        async let groceryRefresh: Void = groceries.refresh()
        let (loaded, _) = try await (snapshot, groceryRefresh)
        guard !Task.isCancelled, session == syncSession, household?.id == id else { return }
        guard let h = loaded.household, loaded.members.contains(where: { $0.userID == userID }) else {
            checkMembership()
            return
        }
        if pendingWrites == 0, revision == writeRevision {
            household = h
            members = loaded.members
            recipes = loaded.recipes
            meals = loaded.meals
            notes = loaded.notes
            reviews = loaded.reviews
            cooks = loaded.cooks
        }
    }

    func refresh() async {
        let session = syncSession
        do { try await reload() } catch {
            guard session == syncSession else { return }
            report(error, source: "household-refresh")
        }
    }

    func resumeSync() async {
        guard phase == .ready else { return }
        if subscription?.isConnected != true {
            await startRealtime()
        }
        await refresh()
        finishedCooks.retry()
        groceries.clearExpired()
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
        let subscribed = await backend.subscribe(household: householdID, user: userID)
        guard session == syncSession else { await subscribed.cancel(); return }
        subscription = subscribed
        realtimeTasks.append(Task { [weak self] in
            for await change in subscribed.changes {
                guard !Task.isCancelled, let self, session == self.syncSession else { return }
                switch change {
                case .groceries: self.groceries.requestReload()
                case .membership: self.checkMembership()
                case .household: self.scheduleReload()
                case .failure(let error): self.report(error, source: "realtime-subscription")
                }
            }
        })
    }

    private func stopRealtime() async {
        for task in realtimeTasks { task.cancel() }
        realtimeTasks = []
        reloadTask?.cancel(); reloadTask = nil
        groceries.cancelReload()
        let previous = subscription
        subscription = nil
        await previous?.cancel()
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
    /// A new recipe is the person's own and follows the Share New Recipes setting unless its owner says otherwise.
    func saveRecipe(_ recipe: Recipe, photo: PhotoChange = .keep, onSaved: (() -> Void)? = nil) {
        guard let userID else { return }
        var recipe = recipe
        let existing = recipes.first { $0.id == recipe.id }
        if existing == nil { recipe.owner = .person(userID, shared: recipe.owner?.isShared ?? PreferenceKey.sharesNewRecipes) }
        let previousPath = existing?.imagePath
        var upload: HouseholdPhotoUpload?
        switch photo {
        case .keep: break
        case .replace(let image):
            // Household recipe photos live with the household; personal ones with their owner.
            guard let folder = recipe.owner == .household ? household?.id : userID,
                  let data = RecipePhotos.uploadData(for: image) else { break }
            let path = "\(folder.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            RecipePhotos.shared.insert(data, for: path)
            recipe.imagePath = path
            upload = .init(path: path, data: data)
        case .remove:
            recipe.imagePath = nil
        }
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        let stalePath = previousPath != recipe.imagePath ? previousPath : nil
        save(.saveRecipe(recipe, isNew: existing == nil, upload: upload, stalePhoto: stalePath), onSuccess: onSaved)
    }

    func deletionExplanation(for recipe: Recipe) -> String {
        let retained = isMine(recipe) && recipe.owner?.isShared == true ? " Your household keeps a separate copy of your shared recipe." : ""
        return "This permanently deletes this recipe. Planned meals keep their saved versions and groceries stay unchanged." + retained
    }

    /// Owners delete their originals, and members delete household recipes. Deleting a shared original
    /// leaves the household a copy. Planned meals keep their saved versions, and groceries stay.
    func deleteRecipe(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        reviews.removeAll { $0.recipeID == recipe.id }
        cooks.removeAll { $0.recipeID == recipe.id }
        for index in meals.indices where meals[index].recipeID == recipe.id { meals[index].recipeID = nil }
        save(.deleteRecipe(recipe.id))
    }

    /// Owner only. Ending sharing leaves the household its own copy; it doesn't retract what was shared.
    func setSharing(_ recipe: Recipe, shared: Bool) {
        guard isMine(recipe), let userID, let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index].owner = .person(userID, shared: shared)
        save(.sharing(recipe.id, shared))
    }

    /// Saves a private copy of another member's or the household's recipe into the person's collection.
    @discardableResult
    func saveCopy(of recipe: Recipe) async throws -> Recipe {
        guard userID != nil else { throw CancellationError() }
        let session = syncSession
        let person = userID
        let copy = try await backend.copyRecipe(recipe.id)
        guard session == syncSession, person == userID else { throw CancellationError() }
        if !recipes.contains(where: { $0.id == copy.id }) { recipes.insert(copy, at: 0) }
        return copy
    }

    /// Favorites are personal, so starring a recipe doesn't change anyone else's list.
    func toggleFavorite(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }), let userID else { return }
        recipes[index].isFavorite.toggle()
        let favorite = recipes[index].isFavorite
        save(.favorite(recipe: recipe.id, user: userID, enabled: favorite))
    }

    private func removePhotos(_ paths: [String]) async { await backend.removePhotos(paths, bucket: .recipe) }

    // MARK: Ratings, notes, and cooked history

    /// Ratings and cooked days for every recipe with either, keyed by recipe ID.
    /// Only current members' ratings count, even before a refetch drops a departed member's.
    var recipeStats: [UUID: RecipeStats] {
        let people = Set(members.map(\.userID) + [userID].compactMap { $0 })
        return RecipeStats.make(reviews: reviews.filter { people.contains($0.userID) }, cooks: cooks, meals: meals)
    }

    /// The person's own rating and note for a recipe, if they've left one.
    func myReview(of recipeID: UUID) -> RecipeReview? {
        reviews.first { $0.recipeID == recipeID && $0.userID == userID }
    }

    /// Other current members' ratings and notes for a recipe, in the order the household lists members.
    func memberReviews(of recipeID: UUID) -> [(member: HouseholdMember, review: RecipeReview)] {
        members.filter { $0.userID != userID }.compactMap { member in
            reviews.first { $0.recipeID == recipeID && $0.userID == member.userID }.map { (member, $0) }
        }
    }

    /// Saves the person's rating and note for a recipe. Clearing both removes the review.
    func saveReview(of recipeID: UUID, rating: Int?, note: String) {
        guard let userID, recipes.contains(where: { $0.id == recipeID }) else { return }
        let review = RecipeReview(userID: userID, recipeID: recipeID, rating: rating.map { min(5, max(1, $0)) },
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        guard review != myReview(of: recipeID) else { return }
        if review.isEmpty {
            reviews.removeAll { $0.recipeID == recipeID && $0.userID == userID }
            save(.review(review))
            return
        }
        if let index = reviews.firstIndex(where: { $0.recipeID == recipeID && $0.userID == userID }) {
            reviews[index] = review
        } else {
            reviews.append(review)
        }
        save(.review(review))
    }

    /// Records that the household cooked a recipe on a day. Marking the same day twice changes nothing,
    /// nor does marking a recipe no longer in the person's recipe book.
    func markCooked(_ recipeID: UUID, on date: Date = .now) {
        recordCook(recipeID, on: date)
    }

    /// Finished cooks stay durable until the idempotent household write is acknowledged.
    private func recordFinishedCook(_ cook: FinishedCook, acknowledge: @escaping (Bool) -> Void) {
        guard cook.accountID == userID else { acknowledge(false); return }
        recordCook(cook.recipeID, on: cook.day, acknowledge: acknowledge)
    }

    private func recordCook(_ recipeID: UUID, on date: Date, acknowledge: ((Bool) -> Void)? = nil) {
        guard let householdID = household?.id else { acknowledge?(false); return }
        // A recipe no longer available cannot receive a marked cook, matching manual marking.
        guard recipes.contains(where: { $0.id == recipeID }) else { acknowledge?(true); return }
        let day = Calendar.current.startOfDay(for: date)
        let alreadyMarked = cooks.contains { $0.recipeID == recipeID && Calendar.current.isDate($0.date, inSameDayAs: day) }
        if !alreadyMarked {
            cooks.append(RecipeCook(recipeID: recipeID, date: day, cookedBy: userID))
        } else if acknowledge == nil { return }
        // Even an optimistic duplicate needs a persistence acknowledgment before leaving the durable queue.
        save(.markCooked(household: householdID, recipe: recipeID, day: day), onCompletion: acknowledge)
    }

    func removeCooked(_ recipeID: UUID, on day: Date) {
        guard let householdID = household?.id else { return }
        cooks.removeAll { $0.recipeID == recipeID && Calendar.current.isDate($0.date, inSameDayAs: day) }
        save(.removeCooked(household: householdID, recipe: recipeID, day: day))
    }

    // MARK: Meal plan

    /// The source recipe as it is now, while it still exists and is available.
    func latestRecipe(for meal: PlannedMeal) -> Recipe? {
        meal.recipeID.flatMap { id in recipes.first { $0.id == id } }
    }

    func hasNewerVersion(_ meal: PlannedMeal) -> Bool {
        latestRecipe(for: meal).map { !$0.hasSameVersion(as: meal.recipe) } ?? false
    }

    /// Adds a recipe to a day and saves its current version. Pass `editing` to change a meal already in
    /// the plan; with `keepVersion`, it keeps its saved recipe version.
    func saveMeal(date: Date, recipe: Recipe, servings: Int, editing: PlannedMeal? = nil, keepVersion: Bool = false) {
        let day = Calendar.current.startOfDay(for: date)
        let kept = keepVersion ? editing : nil
        let meal = PlannedMeal(id: editing?.id ?? UUID(), date: day, recipe: kept?.recipe ?? recipe,
                               recipeID: kept != nil ? kept?.recipeID : recipe.id, servings: servings)
        // Meals stay in the order they were first planned, even when moved to another day.
        if let index = meals.firstIndex(where: { $0.id == editing?.id }) {
            meals[index] = meal
        } else {
            meals.append(meal)
        }
        guard let id = household?.id else { return }
        save(.saveMeal(meal, household: id, keepVersion: kept != nil))
    }

    /// Moves a planned meal to another day, keeping its saved recipe version and servings.
    func moveMeal(_ meal: PlannedMeal, to day: Date) {
        guard !Calendar.current.isDate(meal.date, inSameDayAs: day) else { return }
        saveMeal(date: day, recipe: meal.recipe, servings: meal.servings, editing: meal, keepVersion: true)
    }

    /// Replaces a planned meal's saved version with its recipe's latest. Groceries already added stay as they are.
    func updateMealToLatest(_ meal: PlannedMeal) {
        guard let latest = latestRecipe(for: meal), let index = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        meals[index] = PlannedMeal(id: meal.id, date: meal.date, recipe: latest, recipeID: latest.id, servings: meal.servings)
        save(.updateMeal(meal.id))
    }

    func removeMeal(_ meal: PlannedMeal) { removeMeals([meal]) }

    /// Removes several planned meals in one write.
    func removeMeals(_ removed: [PlannedMeal]) {
        let ids = Set(removed.map(\.id))
        guard !ids.isEmpty else { return }
        meals.removeAll { ids.contains($0.id) }
        save(.removeMeals(Array(ids)))
    }

    /// Adds a note to the meal plan, or saves changes to one already there.
    func saveNote(_ note: MealPlanNote) {
        guard let id = household?.id else { return }
        var note = note
        note.date = Calendar.current.startOfDay(for: note.date)
        note.text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        note.items = note.items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !note.text.isEmpty else { return }
        // Notes stay in the order they were first added, even when moved to another day.
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note } else { notes.append(note) }
        save(.saveNote(note, household: id))
    }

    func moveNote(_ note: MealPlanNote, to day: Date) {
        guard !Calendar.current.isDate(note.date, inSameDayAs: day) else { return }
        var moved = note
        moved.date = day
        saveNote(moved)
    }

    func removeNote(_ note: MealPlanNote) {
        notes.removeAll { $0.id == note.id }
        save(.removeNote(note.id))
    }

    // MARK: Household data

    /// Owner only. Deletes household recipes, the meal plan, and grocery items in one transaction, then
    /// photos nothing uses anymore. Members, their personal recipes, the household, and its invite code remain.
    func deleteAllHouseholdData() async throws {
        guard let id = household?.id else { return }
        // Let earlier edits land first so none of them recreate data afterward.
        await waitForSaves()
        let photoPaths = try await backend.deleteHouseholdData(id)
        guard household?.id == id else { return }
        recipes.removeAll { $0.owner == .household }
        meals = []
        notes = []
        cooks = []
        await removePhotos(photoPaths)
        await refresh()
    }

    // MARK: Account

    /// Deletes the account and personal recipes. The household keeps copies of shared recipes and passes
    /// ownership on, or is deleted when nobody else remains. Then signs out on this device.
    func deleteAccount() async throws {
        guard let userID else { return }
        let session = syncSession
        await waitForSaves()
        guard session == syncSession else { throw CancellationError() }
        try await backend.deleteAccount(userID)
    }

    // MARK: Saving

    /// Waits for writes already queued, including their authoritative refresh.
    func waitForSaves() async {
        repeat { await writeTask?.value } while pendingWrites > 0
    }

    /// Runs a write in the background. On failure, shows the error and refetches so the screen matches the server.
    private func save(_ mutation: HouseholdMutation, onSuccess: (() -> Void)? = nil, onCompletion: ((Bool) -> Void)? = nil) {
        let session = syncSession
        let token = UUID()
        let previous = writeTask
        pendingWrites += 1
        writeRevision &+= 1
        writeTask = Task { [weak self] in
            var acknowledged = false
            defer { onCompletion?(acknowledged) }
            await previous?.value
            guard let self, !Task.isCancelled, session == syncSession else { return }
            defer { savingTasks[token] = nil }
            do {
                try await backend.write(mutation)
                if session == syncSession { acknowledged = true; onSuccess?() }
            } catch { if session == syncSession { report(error, action: mutation.failureAction, recovery: mutation.failureRecovery) } }
            guard session == syncSession else { return }
            pendingWrites -= 1
            writeRevision &+= 1
            if pendingWrites == 0 { await refresh() }
        }
        savingTasks[token] = writeTask
    }

    private func report(_ error: Error, action: String = "update household data", recovery: String = "Reopen Calendish to try again.", source: String = "household-operation") {
        let network = error as NSError
        // URLSession cancellation is distinct from Swift task cancellation. Both
        // are expected when a newer broadcast supersedes an in-flight refresh.
        if Task.isCancelled || error is CancellationError ||
            (network.domain == NSURLErrorDomain && network.code == URLError.cancelled.rawValue) { return }
        HouseholdSyncDiagnostics.record(error, source: source, action: action, phase: String(describing: phase))
        errorTitle = "Couldn’t \(action)"
        errorMessage = InterfaceCopy.recoveryMessage(error, fallback: recovery)
    }
}
