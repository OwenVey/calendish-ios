import Foundation

struct GroceryImportCandidate: Identifiable {
    var recipe: Recipe
    var servings: Int
    var plannedOccurrences = 1
    var id: UUID { recipe.id }

    /// Identical planned versions appear once at their largest serving count. Different saved
    /// versions get independent identities, so review choices cannot overwrite each other.
    static func planned(_ meals: [PlannedMeal]) -> [Self] {
        var candidates: [Self] = []
        var versions: [Recipe] = []
        for meal in meals {
            if let index = versions.firstIndex(where: { $0.id == meal.recipe.id && $0.hasSameVersion(as: meal.recipe) }) {
                candidates[index].servings = max(candidates[index].servings, meal.servings)
                candidates[index].plannedOccurrences += 1
            } else {
                versions.append(meal.recipe)
                var recipe = meal.recipe
                recipe.id = meal.id
                recipe.ingredients = recipe.ingredients.map { Ingredient(text: $0.text) }
                candidates.append(Self(recipe: recipe, servings: meal.servings))
            }
        }
        return candidates
    }

    /// Notes with grocery items, each reviewed like a recipe that can't be scaled.
    static func noted(_ notes: [MealPlanNote]) -> [Self] {
        notes.filter { !$0.items.isEmpty }.map { note in
            let recipe = Recipe(id: note.id, title: note.text, summary: "", prepMinutes: 0, cookMinutes: 0, servings: 0,
                                tags: [], symbol: "", ingredients: note.items.map { Ingredient(text: $0) }, steps: [])
            return Self(recipe: recipe, servings: 0)
        }
    }
}
