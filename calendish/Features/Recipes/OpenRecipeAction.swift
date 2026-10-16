import SwiftUI

/// Shows a saved recipe in the Recipes tab, such as one an import turned out to duplicate.
struct OpenRecipeAction {
    var handler: (Recipe) -> Void = { _ in }

    func callAsFunction(_ recipe: Recipe) {
        handler(recipe)
    }
}

extension EnvironmentValues {
    @Entry var openRecipe = OpenRecipeAction()
}
