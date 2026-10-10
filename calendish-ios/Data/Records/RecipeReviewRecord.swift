import Foundation

nonisolated struct RecipeReviewRecord: Codable, Sendable {
    /// Assigned by the database, for paging. Left out when saving.
    var id = UUID()
    var userID: UUID
    var recipeID: UUID
    var rating: Int?
    var note: String
    var updatedAt: Date?
    enum CodingKeys: String, CodingKey {
        case id, userID = "user_id", recipeID = "recipe_id", rating, note, updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(recipeID, forKey: .recipeID)
        // An explicit null clears a rating when only the note remains.
        try container.encode(rating, forKey: .rating)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
