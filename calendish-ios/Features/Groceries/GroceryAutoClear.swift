import Foundation

/// How long checked-off groceries stay on the list before they're removed for the whole household.
enum GroceryAutoClear: String, CaseIterable, Identifiable {
    case never, hour, day, week
    var id: Self { self }
    var title: String {
        switch self {
        case .never: "Never"
        case .hour: "After an hour"
        case .day: "After a day"
        case .week: "After a week"
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .never: nil
        case .hour: 3600
        case .day: 86_400
        case .week: 604_800
        }
    }
    var explanation: String {
        switch self {
        case .never: "Checked items stay on the list until you clear them."
        case .hour: "Removes items an hour after they’re checked off, for everyone in your household."
        case .day: "Removes items a day after they’re checked off, for everyone in your household."
        case .week: "Removes items a week after they’re checked off, for everyone in your household."
        }
    }
    static var current: GroceryAutoClear {
        UserDefaults.standard.string(forKey: PreferenceKey.groceryAutoClear).flatMap(GroceryAutoClear.init) ?? .never
    }
}
