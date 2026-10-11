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
        case .never: "Checked items stay on the list until someone clears them."
        case .hour: "Checked items are removed an hour after they’re checked off. This applies to everyone in your household."
        case .day: "Checked items are removed a day after they’re checked off. This applies to everyone in your household."
        case .week: "Checked items are removed a week after they’re checked off. This applies to everyone in your household."
        }
    }
}
