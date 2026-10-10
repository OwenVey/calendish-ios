import Foundation

/// A `recipes` row, or a planned meal's saved recipe version, which has the same content without an owner.
nonisolated struct RecipeRecord: Decodable, Sendable {
    var id: UUID
    var ownerID: UUID?
    var householdID: UUID?
    var isShared: Bool?
    var createdAt: Date?
    var title: String
    var summary: String
    var minutes: Int
    var prepMinutes: Int?
    var cookMinutes: Int?
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
        case createdAt = "created_at", ownerID = "owner_id", householdID = "household_id", isShared = "is_shared"
        case id, title, summary, minutes, servings, tags, symbol, ingredients, steps
        case imagePath = "image_path"
        case prepMinutes = "prep_minutes", cookMinutes = "cook_minutes", recipeLink = "recipe_link"
        case category, yieldText = "yield_text"
    }
}
