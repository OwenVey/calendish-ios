import Foundation

/// App values cross this seam; SDK sessions, query builders, and channels stay in the adapter.
struct HouseholdAccount {
    var id: UUID
    var email: String?
    var displayName = ""
    var avatarURL: URL?
}
