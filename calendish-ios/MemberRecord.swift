import Foundation

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
