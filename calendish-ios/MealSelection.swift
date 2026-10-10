import Foundation

struct MealSelection: Identifiable {
    let id = UUID()
    var date = Calendar.current.startOfDay(for: .now)
    var meal: PlannedMeal?
    /// A recipe to preselect when planning from a recipe page.
    var recipeID: UUID?
}
