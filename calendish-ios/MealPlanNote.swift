import Foundation

/// A plan for a day that isn't a recipe, such as "Leftovers" or "Dinner at Mom's", with any groceries it needs.
struct MealPlanNote: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    /// Grocery items to add with the day's meals, such as "Baguette".
    var items: [String] = []
}
