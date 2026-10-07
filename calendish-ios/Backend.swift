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
    enum CodingKeys: String, CodingKey {
        case householdID = "household_id", userID = "user_id", displayName = "display_name", role, avatarURL = "avatar_url"
    }
}

nonisolated struct RecipeRecord: Codable, Sendable {
    var id: UUID
    var householdID: UUID
    var title: String
    var summary: String
    var minutes: Int
    var servings: Int
    var tags: [String]
    var symbol: String
    var ingredients: [Ingredient]
    var steps: [String]
    var isFavorite: Bool
    var imagePath: String?
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", title, summary, minutes, servings, tags, symbol, ingredients, steps
        case isFavorite = "is_favorite", imagePath = "image_path"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdID, forKey: .householdID)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(minutes, forKey: .minutes)
        try container.encode(servings, forKey: .servings)
        try container.encode(tags, forKey: .tags)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
        try container.encode(isFavorite, forKey: .isFavorite)
        // Write an explicit null so removing a photo clears the column.
        try container.encode(imagePath, forKey: .imagePath)
    }
}

nonisolated struct PlannedMealRecord: Codable, Sendable {
    var id: UUID
    var householdID: UUID
    /// A `yyyy-MM-dd` calendar day, so meals land on the same day in every time zone.
    var date: String
    var slot: String
    var recipeID: UUID
    var servings: Int
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", date, slot, recipeID = "recipe_id", servings
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
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", name, amount, source, isComplete = "is_complete", position
    }
}

extension Recipe {
    init(_ row: RecipeRecord) {
        self.init(id: row.id, title: row.title, summary: row.summary, minutes: row.minutes, servings: row.servings,
                  tags: row.tags, symbol: row.symbol, ingredients: row.ingredients, steps: row.steps, isFavorite: row.isFavorite, imagePath: row.imagePath)
    }
    func record(household: UUID) -> RecipeRecord {
        RecipeRecord(id: id, householdID: household, title: title, summary: summary, minutes: minutes, servings: servings,
                  tags: tags, symbol: symbol, ingredients: ingredients, steps: steps, isFavorite: isFavorite, imagePath: imagePath)
    }
}

extension PlannedMeal {
    init?(_ row: PlannedMealRecord) {
        guard let date = DayFormat.date(from: row.date), let slot = MealSlot(rawValue: row.slot) else { return nil }
        self.init(id: row.id, date: date, slot: slot, recipeID: row.recipeID, servings: row.servings)
    }
    func record(household: UUID) -> PlannedMealRecord {
        PlannedMealRecord(id: id, householdID: household, date: DayFormat.string(from: date), slot: slot.rawValue,
                       recipeID: recipeID, servings: servings)
    }
}

extension GroceryItem {
    init(_ row: GroceryItemRecord) {
        self.init(id: row.id, name: row.name, amount: row.amount, source: row.source, isComplete: row.isComplete, position: row.position)
    }
    func record(household: UUID) -> GroceryItemRecord {
        GroceryItemRecord(id: id, householdID: household, name: name, amount: amount, source: source,
                       isComplete: isComplete, position: position)
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
