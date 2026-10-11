import Foundation

/// Planned meals and notes whose ingredients and items to review before adding them to groceries.
struct GroceryReview: Identifiable {
    let id = UUID()
    var meals: [PlannedMeal]
    var notes: [MealPlanNote]
    var candidates: [GroceryImportCandidate] { GroceryImportCandidate.planned(meals) + GroceryImportCandidate.noted(notes) }
}
