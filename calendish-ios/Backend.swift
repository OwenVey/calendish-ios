import Foundation
import Supabase

/// The publishable key is safe to ship in the app: Row Level Security decides what each signed-in user can reach.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://wgtrbwbfazdizkevtwfp.supabase.co")!,
    supabaseKey: "sb_publishable_FIRLJ2Axp-wIyRyznxnrSA_qnr3OvO9",
    options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
)

// Record shapes for each table. Views work with the app models in Models.swift instead.

nonisolated struct HouseholdRecord: Codable, Sendable {
    var id: UUID
    var name: String
    var inviteCode: String
    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
    }
}

nonisolated struct MemberRecord: Codable, Sendable {
    var householdID: UUID
    var userID: UUID
    var displayName: String
    var role: String
    var avatarURL: String?
    var joinedAt: Date?
    enum CodingKeys: String, CodingKey {
        case householdID = "household_id", userID = "user_id", displayName = "display_name", role, avatarURL = "avatar_url"
        case joinedAt = "joined_at"
    }
}

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

/// A new personal recipe. People only create personal recipes; household recipes come from sharing.
nonisolated struct NewRecipeRecord: Encodable, Sendable {
    var id: UUID
    var ownerID: UUID
    var isShared: Bool
    var content: RecipeContentRecord
    enum CodingKeys: String, CodingKey {
        case id, ownerID = "owner_id", isShared = "is_shared"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ownerID, forKey: .ownerID)
        try container.encode(isShared, forKey: .isShared)
        try content.encode(to: encoder)
    }
}

nonisolated struct FavoriteRecord: Codable, Sendable {
    var recipeID: UUID
    enum CodingKeys: String, CodingKey { case recipeID = "recipe_id" }
}

nonisolated struct PlannedMealRecord: Decodable, Sendable {
    var id: UUID
    var householdID: UUID
    /// A `yyyy-MM-dd` calendar day, so meals land on the same day in every time zone.
    var date: String
    var slot: String
    var recipeID: UUID?
    var servings: Int
    /// The recipe version saved when the meal was planned.
    var recipe: RecipeRecord
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", date, slot, recipeID = "recipe_id", servings, recipe
    }
}

nonisolated struct GroceryItemRecord: Codable, Sendable {
    var id: UUID
    var householdID: UUID
    var name: String
    var amount: String
    var source: String
    var isComplete: Bool
    var position: Double
    var aisle: String?
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", name, amount, source, isComplete = "is_complete", position, aisle
    }
}

extension Recipe {
    init(_ row: RecipeRecord, favorites: Set<UUID> = []) {
        self.init(id: row.id, title: row.title, summary: row.summary,
                  prepMinutes: row.prepMinutes ?? 0, cookMinutes: row.cookMinutes ?? row.minutes, servings: row.servings,
                  tags: row.tags, symbol: row.symbol, ingredients: row.ingredients, steps: row.steps,
                  isFavorite: favorites.contains(row.id), imagePath: row.imagePath, recipeLink: row.recipeLink,
                  category: row.category, yieldText: row.yieldText,
                  owner: row.ownerID.map { .person($0, shared: row.isShared ?? false) } ?? (row.householdID == nil ? nil : .household))
    }
    var content: RecipeContentRecord {
        RecipeContentRecord(title: title, summary: summary, minutes: minutes, prepMinutes: prepMinutes, cookMinutes: cookMinutes,
                            servings: servings, tags: tags, symbol: symbol, ingredients: ingredients, steps: steps,
                            imagePath: imagePath, recipeLink: recipeLink, category: category, yieldText: yieldText)
    }
}

extension PlannedMeal {
    init?(_ row: PlannedMealRecord) {
        guard let date = DayFormat.date(from: row.date), let slot = MealSlot(rawValue: row.slot) else { return nil }
        self.init(id: row.id, date: date, slot: slot, recipe: Recipe(row.recipe), recipeID: row.recipeID, servings: row.servings)
    }
}

extension GroceryItem {
    init(_ row: GroceryItemRecord) {
        self.init(id: row.id, name: row.name, amount: row.amount, source: row.source, isComplete: row.isComplete, position: row.position, aisle: row.aisle)
    }
    func record(household: UUID) -> GroceryItemRecord {
        GroceryItemRecord(id: id, householdID: household, name: name, amount: amount, source: source,
                       isComplete: isComplete, position: position, aisle: aisle)
    }
}

/// Converts between local calendar days and Postgres `date` values.
enum DayFormat {
    static func string(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func date(from string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

nonisolated struct SaveMealParameters: Encodable, Sendable {
    var target_household: UUID
    var meal_id: UUID
    var meal_date: String
    var meal_slot: String
    var meal_recipe: UUID?
    var meal_servings: Int
    var moving_id: UUID?
    /// Keeps the moved meal's saved recipe version instead of capturing the recipe's current one.
    var keep_version: Bool

    enum CodingKeys: String, CodingKey {
        case target_household, meal_id, meal_date, meal_slot, meal_recipe, meal_servings, moving_id, keep_version
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(target_household, forKey: .target_household)
        try values.encode(meal_id, forKey: .meal_id)
        try values.encode(meal_date, forKey: .meal_date)
        try values.encode(meal_slot, forKey: .meal_slot)
        // The RPC requires this argument even when a moved meal keeps its saved version.
        try values.encode(meal_recipe, forKey: .meal_recipe)
        try values.encode(meal_servings, forKey: .meal_servings)
        try values.encode(moving_id, forKey: .moving_id)
        try values.encode(keep_version, forKey: .keep_version)
    }
}

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

/// The household a person ends up in after a move, and photos that nothing uses anymore.
nonisolated struct HouseholdMoveResult: Decodable, Sendable {
    var household: HouseholdRecord
    var unusedPhotos: [String]
    enum CodingKeys: String, CodingKey { case household, unusedPhotos = "unused_photos" }
}

nonisolated struct GroceryOrderParameters: Encodable, Sendable {
    var target_household: UUID
    var item_ids: [UUID]
    var item_positions: [Double]
}

nonisolated struct StartHouseholdParameters: Encodable, Sendable {
    var member_name: String
    var code: String?
}
nonisolated struct PreviewMoveParameters: Encodable, Sendable {
    var code: String?
}
nonisolated struct JoinHouseholdParameters: Encodable, Sendable {
    var code: String
    var save_household_recipes: Bool
    var expected_household: UUID?
}
nonisolated struct LeaveHouseholdParameters: Encodable, Sendable {
    var save_household_recipes: Bool
    var expected_household: UUID?
}
nonisolated struct TransferOwnershipParameters: Encodable, Sendable {
    var target_household: UUID
    var new_owner: UUID
}
nonisolated struct RecipeSharingParameters: Encodable, Sendable {
    var target_recipe: UUID
    var shared: Bool
}
