import Foundation

nonisolated struct MealPlanNoteRecord: Codable, Sendable {
    var id: UUID
    var householdID: UUID
    /// A `yyyy-MM-dd` calendar day, like a planned meal's.
    var date: String
    var text: String
    var items: [String]
    /// Notes within a day appear in the order they were added. Left out when saving, so it keeps its first value.
    var createdAt: Date?
    enum CodingKeys: String, CodingKey {
        case id, householdID = "household_id", date, text, items, createdAt = "created_at"
    }
}
