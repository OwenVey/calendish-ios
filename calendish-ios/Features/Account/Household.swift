import Foundation

struct Household: Identifiable {
    var id: UUID
    var name: String
    var inviteCode: String
    /// A link that opens Calendish and offers to join this household.
    var inviteLink: URL { HouseholdInvite.link(for: inviteCode) }
}
