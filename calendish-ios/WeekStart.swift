import Foundation

/// The first day of the meal plan's week. Raw values match `Calendar` weekday numbers; zero follows the region.
enum WeekStart: Int, CaseIterable, Identifiable {
    case system = 0, sunday = 1, monday = 2, saturday = 7
    static let storageKey = "weekStart"
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "Regional default"
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .saturday: "Saturday"
        }
    }
    var weekday: Int { self == .system ? Calendar.current.firstWeekday : rawValue }
    /// The current calendar starting weeks on this day, for date pickers.
    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekday
        return calendar
    }
    static var current: WeekStart { WeekStart(rawValue: UserDefaults.standard.integer(forKey: storageKey)) ?? .system }
}
