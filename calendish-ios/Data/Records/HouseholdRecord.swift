import Foundation

nonisolated struct HouseholdRecord: Codable, Sendable {
    var id: UUID
    var name: String
    var inviteCode: String
    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
    }
}
