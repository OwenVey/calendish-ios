import Foundation

/// The kinds of household alerts, each turned on separately for each account on an installation.
nonisolated enum NotificationTopic: String, CaseIterable, Identifiable, Hashable, Sendable {
    case recipes, groceries, membership
    var id: Self { self }

    var title: String {
        switch self {
        case .recipes: "New recipes"
        case .groceries: "Grocery additions"
        case .membership: "Household members"
        }
    }

    var detail: String {
        switch self {
        case .recipes: "When someone shares a new recipe"
        case .groceries: "When someone adds groceries, grouped into one alert"
        case .membership: "When someone joins, or if you’re removed from the household"
        }
    }

    /// Recipes keep the key they had before there were other topics.
    func preferenceKey(_ account: UUID) -> String {
        switch self {
        case .recipes: "householdRecipeNotifications.\(account.uuidString)"
        case .groceries: "householdGroceryNotifications.\(account.uuidString)"
        case .membership: "householdMembershipNotifications.\(account.uuidString)"
        }
    }
}
