import Foundation

/// Converts between local calendar days and Postgres `date` values.
enum DayFormat {
    /// `yyyy-MM-dd` in the local time zone, always on the Gregorian calendar like Postgres.
    private static var style: Date.ISO8601FormatStyle { Date.ISO8601FormatStyle(timeZone: .current).year().month().day() }
    static func string(from date: Date) -> String {
        date.formatted(style)
    }
    static func date(from string: String) -> Date? {
        try? style.parse(string)
    }
}
