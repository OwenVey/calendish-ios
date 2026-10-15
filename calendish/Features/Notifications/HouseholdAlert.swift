import Foundation

/// A household push notification's route. The recipient and household travel with each alert
/// so an old alert cannot open in another account.
nonisolated struct HouseholdAlert: Hashable {
    enum Kind: String {
        case recipe = "household_recipe", groceries = "household_groceries"
        case memberJoined = "household_member_joined", memberRemoved = "household_member_removed"
    }

    let kind: Kind
    let householdID: UUID
    let recipientID: UUID
    /// Present only for recipe alerts.
    let recipeID: UUID?

    var topic: NotificationTopic {
        switch kind {
        case .recipe: .recipes
        case .groceries: .groceries
        case .memberJoined, .memberRemoved: .membership
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String, let kind = Kind(rawValue: type),
              let household = userInfo["household_id"] as? String, let householdID = UUID(uuidString: household),
              let recipient = userInfo["recipient_id"] as? String, let recipientID = UUID(uuidString: recipient) else { return nil }
        let recipeID = (userInfo["recipe_id"] as? String).flatMap(UUID.init(uuidString:))
        if kind == .recipe, recipeID == nil { return nil }
        self.kind = kind
        self.householdID = householdID
        self.recipientID = recipientID
        self.recipeID = kind == .recipe ? recipeID : nil
    }
}
