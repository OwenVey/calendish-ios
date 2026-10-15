import Foundation

/// The recipient and household travel with the recipe so an old alert cannot open in another account.
nonisolated struct RecipeNotification: Hashable {
    let recipeID: UUID
    let householdID: UUID
    let recipientID: UUID

    init?(userInfo: [AnyHashable: Any]) {
        guard userInfo["type"] as? String == "household_recipe",
              let recipe = userInfo["recipe_id"] as? String, let recipeID = UUID(uuidString: recipe),
              let household = userInfo["household_id"] as? String, let householdID = UUID(uuidString: household),
              let recipient = userInfo["recipient_id"] as? String, let recipientID = UUID(uuidString: recipient) else { return nil }
        self.recipeID = recipeID
        self.householdID = householdID
        self.recipientID = recipientID
    }
}
