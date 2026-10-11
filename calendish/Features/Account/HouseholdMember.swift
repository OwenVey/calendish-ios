import Foundation

struct HouseholdMember: Identifiable {
    var userID: UUID
    var displayName: String
    var role: String
    var avatarURL: URL?
    var id: UUID { userID }
}
