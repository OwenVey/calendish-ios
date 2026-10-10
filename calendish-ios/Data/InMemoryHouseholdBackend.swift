import Foundation

/// A network-free adapter shared by previews and store workflow tests.
/// Database authorization and copy-on-move rules are verified separately against the SQL RPCs.
@MainActor
final class InMemoryHouseholdBackend: HouseholdBackend, GrocerySyncTransport {
    var account: HouseholdAccount?
    var identity = HouseholdAccount(id: UUID(), email: "owen@example.com")
    private var homes: [UUID: HouseholdSnapshot] = [:]
    private var memberships: [UUID: UUID] = [:]
    private var groceryLists: [UUID: [GroceryItem]] = [:]
    private var authObservers: [UUID: AsyncStream<HouseholdAuthChange>.Continuation] = [:]
    private var subscriptions: [UUID: MemoryHouseholdSubscription] = [:]
    var groceryTransport: (any GrocerySyncTransport)? { self }
    var aisleClassifier: (([String]) async -> [String: String])? { nil }

    // Tests can suspend operations with continuations or inject failures without HTTP or timed sleeps.
    var beforeSnapshot: ((UUID) async throws -> Void)?
    var beforeWrite: ((HouseholdMutation) async throws -> Void)?
    var beforeCopy: (() async throws -> Void)?
    var afterMove: (() async throws -> Void)?

    func seed(_ snapshot: HouseholdSnapshot, groceries: [GroceryItem] = []) {
        guard let id = snapshot.household?.id else { return }
        homes[id] = snapshot
        groceryLists[id] = groceries
        for member in snapshot.members { memberships[member.userID] = id }
        if let account { identity = account }
    }
    var authChanges: AsyncStream<HouseholdAuthChange> {
        let id = UUID()
        return AsyncStream { continuation in
            authObservers[id] = continuation
            continuation.yield(.init(account: account))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.authObservers[id] = nil }
            }
        }
    }
    func emitAuth(_ account: HouseholdAccount?, passwordRecovery: Bool = false) {
        self.account = account
        for observer in authObservers.values { observer.yield(.init(account: account, passwordRecovery: passwordRecovery)) }
    }
    func authenticate(_ credentials: HouseholdCredentials) async throws -> Bool {
        switch credentials {
        case .email(let email, _), .signUp(let email, _): identity.email = email; emitAuth(identity)
        case .google: emitAuth(identity)
        case .password, .passwordReset: break
        }
        return true
    }
    func signOut() async throws { emitAuth(nil) }
    func currentHousehold(user: UUID) async throws -> HouseholdRecord? {
        memberships[user].flatMap { homes[$0]?.household }.map { .init(id: $0.id, name: $0.name, inviteCode: $0.inviteCode) }
    }
    func startHousehold(name: String, code: String?) async throws -> HouseholdRecord {
        guard let user = account?.id else { throw CocoaError(.fileWriteNoPermission) }
        if let existing = try await currentHousehold(user: user) { return existing }
        let household: Household
        if let code {
            guard let destination = homes.values.first(where: { $0.household?.inviteCode == code })?.household else { throw rejected("Invitation revoked") }
            household = destination
        } else { household = Household(id: UUID(), name: "My household", inviteCode: String(UUID().uuidString.prefix(8))) }
        var snapshot = homes[household.id] ?? HouseholdSnapshot(household: household)
        snapshot.members.append(HouseholdMember(userID: user, displayName: name, role: snapshot.members.isEmpty ? "owner" : "member"))
        seed(snapshot, groceries: groceryLists[household.id] ?? [])
        return HouseholdRecord(id: household.id, name: household.name, inviteCode: household.inviteCode)
    }
    func snapshot(household: UUID) async throws -> HouseholdSnapshot {
        // Capture before suspending, deliberately allowing tests to deliver an obsolete snapshot.
        let captured = homes[household] ?? HouseholdSnapshot(household: nil)
        try await beforeSnapshot?(household)
        return captured
    }
    func subscribe(household: UUID, user: UUID) async -> any HouseholdSubscription {
        let subscription = MemoryHouseholdSubscription(household: household, user: user)
        subscriptions[subscription.id] = subscription
        subscription.onCancel = { [weak self, weak subscription] in
            if let id = subscription?.id { self?.subscriptions[id] = nil }
        }
        return subscription
    }
    func emit(_ change: HouseholdChange, household: UUID? = nil) {
        for subscription in subscriptions.values where household == nil || subscription.household == household {
            subscription.emit(change)
        }
    }
    func write(_ mutation: HouseholdMutation) async throws {
        guard let user = account?.id, let id = memberships[user], var snapshot = homes[id] else { throw CocoaError(.fileWriteNoPermission) }
        try await beforeWrite?(mutation)
        switch mutation {
        case let .renameHousehold(target, name): if target == id { snapshot.household?.name = name }
        case let .renameMember(target, person, name):
            if target == id, let index = snapshot.members.firstIndex(where: { $0.userID == person }) { snapshot.members[index].displayName = name }
        case let .avatar(target, person, url):
            guard target == id, let index = snapshot.members.firstIndex(where: { $0.userID == person }) else { throw CocoaError(.fileWriteNoPermission) }
            snapshot.members[index].avatarURL = url
        case let .transferOwnership(target, person):
            if target == id { for index in snapshot.members.indices { snapshot.members[index].role = snapshot.members[index].userID == person ? "owner" : "member" } }
        case let .removeMember(target, person):
            if target == id { snapshot.members.removeAll { $0.userID == person }; memberships[person] = nil }
        case let .saveRecipe(recipe, _, _, _):
            if let index = snapshot.recipes.firstIndex(where: { $0.id == recipe.id }) { snapshot.recipes[index] = recipe }
            else { snapshot.recipes.insert(recipe, at: 0) }
        case .deleteRecipe(let recipe):
            snapshot.recipes.removeAll { $0.id == recipe }
            snapshot.reviews.removeAll { $0.recipeID == recipe }
            snapshot.cooks.removeAll { $0.recipeID == recipe }
            for index in snapshot.meals.indices where snapshot.meals[index].recipeID == recipe { snapshot.meals[index].recipeID = nil }
        case let .sharing(recipe, shared):
            if let index = snapshot.recipes.firstIndex(where: { $0.id == recipe }) { snapshot.recipes[index].owner = .person(user, shared: shared) }
        case let .favorite(recipe, _, enabled):
            if let index = snapshot.recipes.firstIndex(where: { $0.id == recipe }) { snapshot.recipes[index].isFavorite = enabled }
        case .review(let review):
            if let index = snapshot.reviews.firstIndex(where: { $0.recipeID == review.recipeID && $0.userID == review.userID }) {
                if review.isEmpty { snapshot.reviews.remove(at: index) } else { snapshot.reviews[index] = review }
            } else if !review.isEmpty { snapshot.reviews.append(review) }
        case let .markCooked(target, recipe, day):
            if target == id, !snapshot.cooks.contains(where: { $0.recipeID == recipe && Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                snapshot.cooks.append(RecipeCook(recipeID: recipe, date: day, cookedBy: user))
            }
        case let .removeCooked(target, recipe, day):
            if target == id { snapshot.cooks.removeAll { $0.recipeID == recipe && Calendar.current.isDate($0.date, inSameDayAs: day) } }
        case let .saveMeal(meal, target, keepVersion):
            guard target == id else { throw CocoaError(.fileWriteNoPermission) }
            var saved = meal
            if let index = snapshot.meals.firstIndex(where: { $0.id == meal.id }) {
                if keepVersion { saved.recipe = snapshot.meals[index].recipe; saved.recipeID = snapshot.meals[index].recipeID }
                snapshot.meals[index] = saved
            } else { snapshot.meals.append(saved) }
        case .updateMeal(let meal):
            if let index = snapshot.meals.firstIndex(where: { $0.id == meal }), let recipe = snapshot.recipes.first(where: { $0.id == snapshot.meals[index].recipeID }) {
                snapshot.meals[index].recipe = recipe
            }
        case .removeMeals(let ids): snapshot.meals.removeAll { ids.contains($0.id) }
        case let .saveNote(note, target):
            guard target == id else { throw CocoaError(.fileWriteNoPermission) }
            if let index = snapshot.notes.firstIndex(where: { $0.id == note.id }) { snapshot.notes[index] = note }
            else { snapshot.notes.append(note) }
        case .removeNote(let note): snapshot.notes.removeAll { $0.id == note }
        }
        homes[id] = snapshot
    }
    func previewMove(code: String?) async throws -> HouseholdMovePreview {
        guard let user = account?.id else { throw CocoaError(.fileWriteNoPermission) }
        let current = memberships[user].flatMap { homes[$0] }
        let destination = code.flatMap { code in homes.values.first { $0.household?.inviteCode == code } }
        if code != nil, destination == nil { throw rejected("Invitation revoked") }
        let others = current?.members.filter { $0.userID != user } ?? []
        let owned = current?.recipes.filter { $0.owner?.person == user } ?? []
        return HouseholdMovePreview(destination: destination?.household.map { .init(id: $0.id, name: $0.name, members: destination!.members.map(\.displayName)) },
            currentHouseholdID: current?.household?.id, currentHouseholdName: current?.household?.name,
            isCurrent: destination?.household?.id == current?.household?.id && destination != nil,
            otherMembers: others.count, successor: others.first.map { .init(userID: $0.userID, displayName: $0.displayName) },
            deletesHousehold: others.isEmpty, personalRecipes: owned.count, sharedRecipes: owned.filter { $0.owner?.isShared == true }.count,
            householdRecipes: current?.recipes.filter { $0.owner == .household }.count ?? 0,
            plannedMeals: current?.meals.count ?? 0, groceries: memberships[user].flatMap { groceryLists[$0]?.count } ?? 0)
    }
    func move(code: String?, saveRecipes: Bool, expected: UUID?) async throws -> HouseholdMoveResult {
        guard let user = account?.id, memberships[user] == expected else { throw rejected("Household changed. Review the move again.") }
        let old = memberships[user].flatMap { homes[$0] }
        let destination: Household
        if let code {
            guard let home = homes.values.first(where: { $0.household?.inviteCode == code })?.household else { throw rejected("Invitation revoked") }
            destination = home
        } else { destination = Household(id: UUID(), name: "My household", inviteCode: String(UUID().uuidString.prefix(8))) }
        if destination.id != expected {
            if let expected { homes[expected]?.members.removeAll { $0.userID == user } }
            var next = homes[destination.id] ?? HouseholdSnapshot(household: destination)
            if !next.members.contains(where: { $0.userID == user }) {
                next.members.append(HouseholdMember(userID: user, displayName: old?.members.first { $0.userID == user }?.displayName ?? "Me", role: next.members.isEmpty ? "owner" : "member"))
            }
            let recipes = old?.recipes.filter { $0.owner?.person == user || (saveRecipes && $0.owner == .household) } ?? []
            for var recipe in recipes where !next.recipes.contains(where: { $0.id == recipe.id }) {
                if recipe.owner == .household { recipe.id = UUID(); recipe.owner = .person(user, shared: false) }
                next.recipes.append(recipe)
            }
            seed(next, groceries: groceryLists[destination.id] ?? [])
        }
        try await afterMove?()
        return HouseholdMoveResult(household: .init(id: destination.id, name: destination.name, inviteCode: destination.inviteCode), unusedPhotos: [])
    }
    func copyRecipe(_ id: UUID) async throws -> Recipe {
        guard let user = account?.id, let home = memberships[user], var recipe = homes[home]?.recipes.first(where: { $0.id == id }) else { throw CocoaError(.fileReadNoSuchFile) }
        recipe.id = UUID(); recipe.owner = .person(user, shared: false); recipe.isFavorite = false
        try await beforeCopy?()
        homes[home]?.recipes.insert(recipe, at: 0)
        return recipe
    }
    func deleteHouseholdData(_ id: UUID) async throws -> [String] {
        homes[id]?.recipes.removeAll { $0.owner == .household }
        homes[id]?.meals = []; homes[id]?.notes = []; homes[id]?.cooks = []
        groceryLists[id] = []
        return []
    }
    func deleteAccount(_ user: UUID) async throws {
        if let id = memberships[user] { homes[id]?.members.removeAll { $0.userID == user }; homes[id]?.recipes.removeAll { $0.owner?.person == user } }
        memberships[user] = nil
        emitAuth(nil)
    }
    func uploadPhoto(_ upload: HouseholdPhotoUpload, bucket: HouseholdPhotoBucket) async throws { }
    func removePhotos(_ paths: [String], bucket: HouseholdPhotoBucket) async { }
    func avatar(household: UUID, user: UUID) async throws -> URL? { homes[household]?.members.first { $0.userID == user }?.avatarURL }
    private func rejected(_ message: String) -> HouseholdMoveRejected { .init(underlying: NSError(domain: message, code: 1, userInfo: [NSLocalizedDescriptionKey: message])) }
    func fetch(householdID: UUID) async throws -> [GroceryItem] { groceryLists[householdID] ?? [] }
    func write(_ mutation: GroceryMutation, householdID: UUID) async throws {
        var items = groceryLists[householdID] ?? []
        for change in mutation.changes { change.apply(to: &items) }
        groceryLists[householdID] = items
    }
}
