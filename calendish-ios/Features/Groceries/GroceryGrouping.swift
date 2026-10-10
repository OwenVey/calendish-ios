import Foundation

enum GroceryGrouping: String, CaseIterable, Identifiable {
    case none = "None", recipe = "Recipe", aisle = "Aisle"
    var id: Self { self }
}
