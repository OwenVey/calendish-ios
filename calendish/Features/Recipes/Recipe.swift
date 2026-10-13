import Foundation

struct Recipe: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var summary: String
    var prepMinutes: Int
    var cookMinutes: Int
    var minutes: Int { prepMinutes + cookMinutes }
    var servings: Int
    var tags: [String]
    var symbol: String
    var ingredients: [Ingredient]
    var steps: [String]
    var isFavorite = false
    /// Where the photo lives in the `recipe-images` bucket, or nil when there's no photo.
    var imagePath: String?
    var recipeLink: String?
    /// The kind of dish, kept apart from free-form tags.
    var category: RecipeCategory?
    /// What the recipe makes when that isn't just servings, such as "24 cookies".
    var yieldText: String?
    /// Who the recipe belongs to. Nil for a planned meal's saved version.
    var owner: RecipeOwner?
    /// Counts content edits on the server, so a save can confirm it captures the version someone reviewed.
    /// Nil for a planned meal's saved version.
    var revision: Int?

    // Keep synthesized value equality: Observation compares recipe arrays before
    // notifying views. ID-only equality hides edits to an existing recipe.

    /// Whether two recipes have the same cooking content, ignoring who owns or favorited them.
    func hasSameVersion(as other: Recipe) -> Bool {
        var mine = self, theirs = other
        mine.owner = nil; theirs.owner = nil
        mine.isFavorite = false; theirs.isFavorite = false
        mine.revision = nil; theirs.revision = nil
        mine.id = theirs.id
        return mine == theirs
    }

    /// Whether a search matches the title, summary, category, tags, or any ingredient.
    func matches(_ search: String) -> Bool {
        search.isEmpty || ([title, summary, category?.title ?? ""] + tags + ingredients.map(\.text)).contains { $0.localizedStandardContains(search) }
    }
}
