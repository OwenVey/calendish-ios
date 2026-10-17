import Foundation

/// Adds groceries someone asked Siri or Shortcuts for, without the app on screen.
/// Items are stored exactly as spoken, like typing them into the list.
@MainActor
struct SpokenGroceryAdd {
    enum Outcome: Equatable {
        case added(String)
        /// An unchecked item for the same food is already on the list, by `GroceryFood`'s rule.
        case alreadyOnList(String)

        var name: String {
            switch self { case .added(let name), .alreadyOnList(let name): name }
        }
    }

    enum Failure: Error {
        /// Signed out, or signed in without a household yet.
        case noHousehold
    }

    let userID: () -> UUID?
    let household: (UUID) async throws -> UUID?
    let transport: any GrocerySyncTransport

    /// Returns only once every added item is saved, so callers never confirm an item the household can't see.
    func add(_ items: [String]) async throws -> [Outcome] {
        guard let user = userID(), let householdID = try await household(user) else { throw Failure.noHousehold }
        let existing = try await transport.fetch(householdID: householdID)
        var onList = GroceryFood.onList(existing)
        var names: [String] = []
        let outcomes = GroceryItem.addableNames(items).map { name -> Outcome in
            guard onList.insert(GroceryFood.key(of: name)).inserted else { return .alreadyOnList(name) }
            names.append(name)
            return .added(name)
        }
        let added = GroceryItem.general(named: names, after: existing)
        if !added.isEmpty { try await transport.write(.insert(added), householdID: householdID) }
        return outcomes
    }
}
