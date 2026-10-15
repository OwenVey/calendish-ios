import Foundation

@MainActor
enum HouseholdNotificationTests {
    static func run() throws {
        let recipe = UUID(), home = UUID(), recipient = UUID()
        let payload: [AnyHashable: Any] = ["type": "household_recipe", "recipe_id": recipe.uuidString,
                                          "household_id": home.uuidString, "recipient_id": recipient.uuidString]
        let route = HouseholdAlert(userInfo: payload)
        try expect(route?.kind == .recipe && route?.recipeID == recipe && route?.householdID == home && route?.recipientID == recipient,
                   "Notification routing preserves its recipe, household, and recipient")
        var malformed = payload
        malformed["recipient_id"] = nil
        try expect(HouseholdAlert(userInfo: malformed) == nil, "An alert without a recipient cannot route across accounts")
        malformed = payload; malformed["household_id"] = "invalid"
        try expect(HouseholdAlert(userInfo: malformed) == nil, "Malformed household IDs are rejected")
        malformed = payload; malformed["type"] = "cooking_timer"
        try expect(HouseholdAlert(userInfo: malformed) == nil, "Cooking alerts are not treated as household alerts")
        malformed = payload; malformed["recipe_id"] = nil
        try expect(HouseholdAlert(userInfo: malformed) == nil, "A recipe alert needs its recipe")

        var groceries = payload
        groceries["type"] = "household_groceries"
        groceries["recipe_id"] = nil
        let grocery = HouseholdAlert(userInfo: groceries)
        try expect(grocery?.kind == .groceries && grocery?.topic == .groceries && grocery?.recipeID == nil,
                   "Grocery alerts route to the grocery list")
        for type in ["household_member_joined", "household_member_removed"] {
            var membership = groceries
            membership["type"] = type
            try expect(HouseholdAlert(userInfo: membership)?.topic == .membership, "Membership alerts share one setting")
        }

        let data = try JSONEncoder().encode(PushDeviceRegistration(installation: UUID(), device_token: String(repeating: "a", count: 64),
                                                                push_environment: "sandbox", recipes_enabled: true,
                                                                groceries_enabled: false, membership_enabled: true))
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try expect(body?["recipes_enabled"] as? Bool == true, "Device registration encodes an actual boolean")
        try expect(body?["groceries_enabled"] as? Bool == false && body?["membership_enabled"] as? Bool == true,
                   "Each topic registers separately")
        try expect(body?["push_environment"] as? String == "sandbox", "Development tokens register in the sandbox")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }
}
