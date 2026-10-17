import Foundation

/// The one rule for whether two grocery lines are the same food. "1 large onion, diced", "2 onions", and
/// "onion" are all onion, whatever their amount or case. Every way of adding groceries checks the list with it.
enum GroceryFood {
    /// The food a line names, reduced so the same food written differently matches. Lines that name no food,
    /// such as "Salt to taste" without a parsed name, fall back to the whole line.
    static func key(of line: String) -> String {
        let food = IngredientParser.foodKey(of: line)
        return food.isEmpty ? line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : food
    }

    static func key(of item: GroceryItem) -> String { key(of: text(of: item)) }

    /// The item as one line, as it was written or merged.
    static func text(of item: GroceryItem) -> String {
        [item.amount, item.name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The foods on the list, optionally only those needed for `source`. Checked-off items don't count,
    /// so they can be bought again. Check a line with `contains(key(of: line))`.
    static func onList(_ groceries: [GroceryItem], for source: String? = nil) -> Set<String> {
        Set(groceries.filter { !$0.isComplete && (source.map($0.sources.contains) ?? true) }.map { key(of: $0) })
    }
}
