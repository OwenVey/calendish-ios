import Foundation

nonisolated struct GroceryFields: Encodable, Sendable {
    var name: String?
    var amount: String?
    var source: String?
    var isComplete: Bool?
    enum CodingKeys: String, CodingKey {
        case name, amount, source, isComplete = "is_complete"
    }
}
