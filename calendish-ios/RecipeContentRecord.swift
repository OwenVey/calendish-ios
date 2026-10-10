import Foundation

/// The recipe fields an editor may change. Ownership and sharing change only through database functions.
nonisolated struct RecipeContentRecord: Encodable, Sendable {
    var title: String
    var summary: String
    var minutes: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var servings: Int
    var tags: [String]
    var symbol: String
    var ingredients: [Ingredient]
    var steps: [String]
    var imagePath: String?
    var recipeLink: String?
    var category: String?
    var yieldText: String?
    enum CodingKeys: String, CodingKey {
        case title, summary, minutes, servings, tags, symbol, ingredients, steps
        case imagePath = "image_path", prepMinutes = "prep_minutes", cookMinutes = "cook_minutes", recipeLink = "recipe_link"
        case category, yieldText = "yield_text"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(minutes, forKey: .minutes)
        try container.encode(prepMinutes, forKey: .prepMinutes)
        try container.encode(cookMinutes, forKey: .cookMinutes)
        try container.encode(servings, forKey: .servings)
        try container.encode(tags, forKey: .tags)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
        // Write explicit nulls so clearing a field, such as removing a photo, clears the column.
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(recipeLink, forKey: .recipeLink)
        try container.encode(category, forKey: .category)
        try container.encode(yieldText, forKey: .yieldText)
    }
}
