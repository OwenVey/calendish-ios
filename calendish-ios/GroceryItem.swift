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
}
