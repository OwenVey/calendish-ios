import Foundation

/// What a household move would do, from `preview_household_move`.
nonisolated struct HouseholdMovePreview: Decodable, Sendable, Equatable {
    nonisolated struct Destination: Decodable, Sendable, Equatable {
        var id: UUID
        var name: String
        var members: [String]
    }
    nonisolated struct Successor: Decodable, Sendable, Equatable {
        var userID: UUID
        var displayName: String
        enum CodingKeys: String, CodingKey { case userID = "user_id", displayName = "display_name" }
    }
    var destination: Destination?
    var currentHouseholdID: UUID?
    var currentHouseholdName: String?
    var isCurrent: Bool
    var otherMembers: Int
    var successor: Successor?
    var deletesHousehold: Bool
    var personalRecipes: Int
    var sharedRecipes: Int
    var householdRecipes: Int
    var plannedMeals: Int
    var groceries: Int
    enum CodingKeys: String, CodingKey {
        case destination, successor, groceries
        case currentHouseholdID = "current_household_id", currentHouseholdName = "current_household_name"
        case isCurrent = "is_current", otherMembers = "other_members", deletesHousehold = "deletes_household"
        case personalRecipes = "personal_recipes", sharedRecipes = "shared_recipes"
        case householdRecipes = "household_recipes", plannedMeals = "planned_meals"
    }
}
