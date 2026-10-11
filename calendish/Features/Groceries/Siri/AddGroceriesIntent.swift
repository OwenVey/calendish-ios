import AppIntents
import Foundation

/// Adds items to the household grocery list from Shortcuts, Spotlight, or Siri, without opening the app.
struct AddGroceriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Groceries"
    static let description = IntentDescription("Adds items to your household’s grocery list.")

    @Parameter(title: "Items", requestValueDialog: "What do you want to add?")
    var items: [String]

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$items) to groceries") }

    init() { }
    init(items: [String]) { self.items = items }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Shortcuts may pass a block of text, one item per line.
        let items = items.flatMap { $0.split(whereSeparator: \.isNewline).map(String.init) }
        guard let adder = SpokenGroceryAdd.live() else { return .result(dialog: "\(SpokenGroceryAdd.noHouseholdReply)") }
        do {
            let outcomes = try await adder.add(items)
            guard !outcomes.isEmpty else { return .result(dialog: "\(SpokenGroceryAdd.nothingToAddReply)") }
            return .result(dialog: "\(SpokenGroceryAdd.reply(to: outcomes))")
        } catch SpokenGroceryAdd.Failure.noHousehold {
            return .result(dialog: "\(SpokenGroceryAdd.noHouseholdReply)")
        } catch {
            return .result(dialog: "\(SpokenGroceryAdd.failedReply(for: items))")
        }
    }
}

struct CalendishShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddGroceriesIntent(), phrases: [
            "Add to \(.applicationName)",
            "Add to my \(.applicationName) groceries",
            "Add groceries in \(.applicationName)",
        ], shortTitle: "Add to Groceries", systemImageName: "cart.badge.plus")
    }
}
