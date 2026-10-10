import Foundation

nonisolated struct FavoriteRecord: Codable, Sendable {
    var recipeID: UUID
    enum CodingKeys: String, CodingKey { case recipeID = "recipe_id" }
}
