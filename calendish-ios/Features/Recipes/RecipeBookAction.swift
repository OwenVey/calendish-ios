import Foundation

/// Something to do with a recipe from the recipe book's rows, cards, and context menus.
enum RecipeBookAction {
    case plan(Recipe)
    case addToGroceries(Recipe)
    case delete(Recipe)
}
