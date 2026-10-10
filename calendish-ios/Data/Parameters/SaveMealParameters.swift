import Foundation

nonisolated struct SaveMealParameters: Encodable, Sendable {
    var target_household: UUID
    var meal_id: UUID
    var meal_date: String
    var meal_recipe: UUID?
    var meal_servings: Int
    /// Keeps an existing meal's saved recipe version instead of capturing the recipe's current one.
    var keep_version: Bool

    enum CodingKeys: String, CodingKey {
        case target_household, meal_id, meal_date, meal_recipe, meal_servings, keep_version
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(target_household, forKey: .target_household)
        try values.encode(meal_id, forKey: .meal_id)
        try values.encode(meal_date, forKey: .meal_date)
        // The RPC requires this argument even when an existing meal keeps its saved version.
        try values.encode(meal_recipe, forKey: .meal_recipe)
        try values.encode(meal_servings, forKey: .meal_servings)
        try values.encode(keep_version, forKey: .keep_version)
    }
}
