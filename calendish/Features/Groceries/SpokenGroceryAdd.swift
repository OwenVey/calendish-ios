import Foundation

/// Adds groceries someone asked Siri or Shortcuts for, without the app on screen.
/// Items are stored exactly as spoken, like typing them into the list.
@MainActor
struct SpokenGroceryAdd {
    enum Outcome: Equatable {
        case added(String)
        /// An unchecked item with the same name is already on the list. Checked-off items don't count, so they can be bought again.
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
        let names = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let existing = try await transport.fetch(householdID: householdID)
        var onList = Set(existing.filter { !$0.isComplete }.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var added: [GroceryItem] = []
        var position = existing.map(\.position).max() ?? 0
        let outcomes = names.map { name -> Outcome in
            guard onList.insert(name.lowercased()).inserted else { return .alreadyOnList(name) }
            position += 1
            added.append(GroceryItem(name: name, amount: "", source: "General", position: position))
            return .added(name)
        }
        if !added.isEmpty { try await transport.write(.insert(added), householdID: householdID) }
        return outcomes
    }
}
