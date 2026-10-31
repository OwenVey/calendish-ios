import Foundation

struct GroceryItem: Identifiable {
    var id = UUID()
    var name: String
    var amount: String
    var source: String
    var isComplete = false
    var position: Double = 0
    /// A `GroceryAisle` raw value, or nil until the item has been sorted.
    var aisle: String?

    /// The recipes this item is for. An item merged from several recipes stores each title on its own line of `source`.
    var sources: [String] {
        get { source.split(separator: "\n").map(String.init) }
        set { source = newValue.joined(separator: "\n") }
    }

    /// Ordinary groceries named as typed or spoken, after everything on `list`, in the given order.
    /// Names are trimmed and blank ones skipped; a repeated name gets its own row.
    static func general(named names: [String], after list: [GroceryItem]) -> [GroceryItem] {
        let start = list.map(\.position).max() ?? 0
        return addableNames(names).enumerated().map { index, name in
            GroceryItem(name: name, amount: "", source: "General", position: start + Double(index + 1))
        }
    }

    /// The names `general(named:after:)` would add, trimmed and without blanks.
    static func addableNames(_ names: [String]) -> [String] {
        names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
