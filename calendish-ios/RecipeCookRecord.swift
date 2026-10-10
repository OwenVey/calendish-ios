import Foundation

nonisolated struct RecipeCookRecord: Codable, Sendable {
    /// Assigned by the database, for paging. Left out when saving.
    var id = UUID()
    var householdID: UUID
    var recipeID: UUID
    /// A `yyyy-MM-dd` calendar day, like a planned meal's.
    var cookedOn: String
    /// Filled in by the database when saving.
    var cookedBy: UUID?
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", recipeID = "recipe_id", cookedOn = "cooked_on", cookedBy = "cooked_by"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdID, forKey: .householdID)
        try container.encode(recipeID, forKey: .recipeID)
        try container.encode(cookedOn, forKey: .cookedOn)
    }
}
