import Foundation

/// Planned meals and notes to remove once confirmed.
struct PlanRemoval {
    var meals: [PlannedMeal] = []
    var notes: [MealPlanNote] = []
    /// Removing everything planned in one week, from its menu.
    var clearsWeek = false
    /// Removing every planned meal and note, including weeks outside the visible range.
    var clearsAll = false

    var title: String {
        if clearsAll { return "Clear the entire meal plan?" }
        if clearsWeek { return "Clear this week?" }
        return switch (meals.count, notes.count) {
        case (0, 1): "Remove this note?"
        case (0, _): "Remove these notes?"
        case (1, 0): "Remove this planned meal?"
        case (_, 0): "Remove these planned meals?"
        default: "Clear this day?"
        }
    }
    var buttonTitle: String {
        if clearsAll { return "Clear meal plan" }
        if clearsWeek { return "Clear week" }
        return switch (meals.count, notes.count) {
        case (0, 1): "Remove note"
        case (0, _): "Remove notes"
        case (1, 0): "Remove meal"
        case (_, 0): "Remove meals"
        default: "Clear day"
        }
    }
    var message: String? {
        if clearsAll {
            return "Removes all planned meals and notes from every week for everyone in your household. Your recipes and grocery list stay saved."
        }
        if clearsWeek {
            let removed = [meals.isEmpty ? nil : meals.count == 1 ? "1 planned meal" : "\(meals.count) planned meals",
                           notes.isEmpty ? nil : notes.count == 1 ? "1 note" : "\(notes.count) notes"].compactMap(\.self)
            return "Removes \(removed.joined(separator: " and ")) from this week for everyone in your household."
                + (meals.isEmpty ? "" : " The recipes stay in your recipe book.")
        }
        return switch meals.count {
        case 0: nil
        case 1: "The recipe stays in your recipe book."
        default: "The recipes stay in your recipe book."
        }
    }
}
