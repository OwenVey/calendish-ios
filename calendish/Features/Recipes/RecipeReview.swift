import Foundation

/// One person's rating and note for a recipe, such as four stars and "Use half the salt". The household sees each member's.
struct RecipeReview: Hashable {
    var userID: UUID
    var recipeID: UUID
    /// One to five stars, or nil when the person only left a note.
    var rating: Int?
    var note: String = ""
    var isEmpty: Bool { rating == nil && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
