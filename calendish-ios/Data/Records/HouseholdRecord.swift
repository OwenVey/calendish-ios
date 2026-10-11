import Foundation

nonisolated struct HouseholdRecord: Codable, Sendable {
    var id: UUID
    var name: String
    var inviteCode: String
    var groceryAutoClear: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case groceryAutoClear = "grocery_auto_clear"
    }
}

extension HouseholdRecord {
    var household: Household {
        Household(id: id, name: name, inviteCode: inviteCode,
            groceryAutoClear: groceryAutoClear.flatMap(GroceryAutoClear.init) ?? .never)
    }
}
