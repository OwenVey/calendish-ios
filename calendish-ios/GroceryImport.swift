import Foundation

/// What adding reviewed lines does to the grocery list: new items, and unchecked items that absorbed a line.
struct GroceryImport {
    var added: [GroceryItem] = []
    var updated: [(item: GroceryItem, original: GroceryItem)] = []
    var isEmpty: Bool { added.isEmpty && updated.isEmpty }
}
