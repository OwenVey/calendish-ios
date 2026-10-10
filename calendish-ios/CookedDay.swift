import Foundation

/// One day in a recipe's cooked history, and how it got there. A day can be both marked and a past planned meal.
struct CookedDay: Hashable {
    var date: Date
    /// Recorded by a member. Only marked days can be removed; removing one leaves any planned meal that day.
    var isMarked: Bool
    /// A past planned meal of the recipe, which leaves the history only when removed from the meal plan.
    var isPlanned: Bool
}
