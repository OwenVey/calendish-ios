import Foundation

/// Planned meals and notes to remove once confirmed.
struct PlanRemoval {
    var meals: [PlannedMeal] = []
    var notes: [MealPlanNote] = []
    /// Removing every planned meal on every day, from the toolbar.
    var clearsPlan = false

    var title: String {
        if clearsPlan { return "Clear all planned meals?" }
        return switch (meals.count, notes.count) {
        case (0, 1): "Remove this note?"
        case (0, _): "Remove these notes?"
        case (1, 0): "Remove this planned meal?"
        case (_, 0): "Remove these planned meals?"
        default: "Clear this day?"
        }
    }
    var buttonTitle: String {
        if clearsPlan { return "Clear meal plan" }
        return switch (meals.count, notes.count) {
        case (0, 1): "Remove note"
        case (0, _): "Remove notes"
        case (1, 0): "Remove meal"
        case (_, 0): "Remove meals"
        default: "Clear day"
        }
    }
    var message: String? {
        if clearsPlan { return "Removes \(meals.count) planned \(meals.count == 1 ? "meal" : "meals") from every day. Notes stay, and the recipes stay in your recipe book." }
        return switch meals.count {
        case 0: nil
        case 1: "The recipe stays in your recipe book."
        default: "The recipes stay in your recipe book."
        }
    }
}
