import Foundation

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
