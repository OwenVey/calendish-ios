import Foundation

struct PlannedMeal: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    /// The recipe as it was when planned. Later edits or deletion of the source don't change it.
    var recipe: Recipe
    /// The source recipe, while it still exists, for an explicit update to its latest version.
    var recipeID: UUID?
    var servings: Int

    init(id: UUID = UUID(), date: Date, recipe: Recipe, recipeID: UUID?, servings: Int) {
        self.id = id
        self.date = date
        var saved = recipe
        saved.owner = nil
        saved.isFavorite = false
        saved.revision = nil
        self.recipe = saved
        self.recipeID = recipeID
        self.servings = servings
    }
}
