import Foundation

nonisolated struct AddMealParameters: Encodable, Sendable {
    var target_household: UUID
    var meal_id: UUID
    var meal_date: String
    var meal_recipe: UUID
    var expected_revision: Int
    var meal_servings: Int
}
