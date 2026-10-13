import Foundation

enum CalendarDays {
    static func startOfWeek(_ date: Date, weekStart: WeekStart = .current) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - weekStart.weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    static func week(containing date: Date, weekStart: WeekStart = .current) -> [Date] {
        let start = startOfWeek(date, weekStart: weekStart)
        return (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
    }
}
