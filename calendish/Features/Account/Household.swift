import Foundation

struct Household: Identifiable {
    var id: UUID
    var name: String
    var inviteCode: String
    /// Shared by every member, since clearing removes items from everyone's list.
    var groceryAutoClear = GroceryAutoClear.never
    /// A link that opens Calendish and offers to join this household.
    var inviteLink: URL { HouseholdInvite.link(for: inviteCode) }
}
