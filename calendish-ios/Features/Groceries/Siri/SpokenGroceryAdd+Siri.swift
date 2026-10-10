import Foundation

extension SpokenGroceryAdd {
    /// The signed-in household's list, read from the saved session so it works with the app in the background.
    static func live(backend: any HouseholdBackend = SupabaseHouseholdBackend()) -> SpokenGroceryAdd? {
        guard let transport = backend.groceryTransport else { return nil }
        return SpokenGroceryAdd(userID: { backend.account?.id },
                                household: { try await backend.currentHousehold(user: $0)?.id },
                                transport: transport)
    }

    /// What Siri says back, shared by every way of adding groceries by voice.
    nonisolated static func reply(to outcomes: [Outcome]) -> String {
        let added = outcomes.compactMap { if case .added(let name) = $0 { name } else { nil } }
        let skipped = outcomes.compactMap { if case .alreadyOnList(let name) = $0 { name } else { nil } }
        var sentences: [String] = []
        if !added.isEmpty { sentences.append("Added \(added.formatted(.list(type: .and))) to your grocery list.") }
        if !skipped.isEmpty {
            let verb = skipped.count == 1 ? "is" : "are"
            sentences.append("\(skipped.formatted(.list(type: .and)).capitalizedFirst) \(verb) already on your list.")
        }
        return sentences.joined(separator: " ")
    }

    nonisolated static let noHouseholdReply = "Open Calendish to set up your household first."
    nonisolated static let nothingToAddReply = "There was nothing to add."
    nonisolated static func failedReply(for items: [String]) -> String {
        "Couldn’t confirm \(items.formatted(.list(type: .and))) \(items.count == 1 ? "was" : "were") added. Check your grocery list before trying again."
    }
}

private extension String {
    nonisolated var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
