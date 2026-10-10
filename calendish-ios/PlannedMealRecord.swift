import Foundation

nonisolated struct PlannedMealRecord: Decodable, Sendable {
    var id: UUID
    var householdID: UUID
    /// A `yyyy-MM-dd` calendar day, so meals land on the same day in every time zone.
    var date: String
    var recipeID: UUID?
    var servings: Int
    /// The recipe version saved when the meal was planned.
    var recipe: RecipeRecord
    /// Meals within a day appear in the order they were planned.
    var createdAt: Date?
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", date, recipeID = "recipe_id", servings, recipe, createdAt = "created_at"
    }
}
