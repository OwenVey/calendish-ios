import Foundation

/// The days a household cooked one recipe: marked cooks plus past planned meals, most recent first.
struct CookedHistory: Hashable {
    private(set) var days: [CookedDay] = []
    var lastCooked: Date? { days.first?.date }

    func contains(_ day: Date) -> Bool {
        days.contains { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    /// Whether a member marked the recipe cooked on a day.
    func isMarked(on day: Date) -> Bool {
        days.contains { $0.isMarked && Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    /// Histories for every recipe cooked at least once, keyed by recipe ID. Planned meals count from the day after they were planned.
    static func make(cooks: [RecipeCook], meals: [PlannedMeal], now: Date = .now) -> [UUID: CookedHistory] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var days: [UUID: [Date: CookedDay]] = [:]
        for cook in cooks {
            let day = calendar.startOfDay(for: cook.date)
            days[cook.recipeID, default: [:]][day, default: CookedDay(date: day, isMarked: false, isPlanned: false)].isMarked = true
        }
        for meal in meals {
            guard let id = meal.recipeID else { continue }
            let day = calendar.startOfDay(for: meal.date)
            guard day < today else { continue }
            days[id, default: [:]][day, default: CookedDay(date: day, isMarked: false, isPlanned: false)].isPlanned = true
        }
        return days.mapValues { CookedHistory(days: $0.values.sorted { $0.date > $1.date }) }
    }

    /// The recipe in the person's recipe book that cooking `recipe` counts toward, which ratings and notes belong to as well.
    /// A planned meal's saved version counts toward its source recipe while that still exists.
    static func recipeID(cooking recipe: Recipe, plannedMeal: PlannedMeal? = nil, in book: [Recipe]) -> UUID? {
        let id = plannedMeal == nil ? recipe.id : plannedMeal?.recipeID
        return id.flatMap { id in book.contains { $0.id == id } ? id : nil }
    }

    /// Names whether the latest history day was marked cooked or only planned.
    static func lastCookedText(_ history: CookedHistory?, now: Date = .now) -> String {
        guard let day = history?.days.first else { return "No cooking recorded" }
        let source = day.isMarked ? "Last marked cooked" : "Last planned"
        return "\(source) \(cookedAgo(day.date, now: now))"
    }

    /// "today", "yesterday", "3 weeks ago", or similar, counted in calendar days, to follow "Last cooked".
    static func cookedAgo(_ day: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0)
        let formatter = RelativeDateTimeFormatter()
        // Named styles read "last week" past a few days, which doesn't follow "Last cooked" well.
        formatter.dateTimeStyle = days < 7 ? .named : .numeric
        let components: DateComponents = switch days {
        case ..<7: DateComponents(day: -days)
        case ..<30: DateComponents(weekOfMonth: -(days / 7))
        case ..<365: DateComponents(month: -max(1, days / 30))
        default: DateComponents(year: -(days / 365))
        }
        return formatter.localizedString(from: components)
    }
}
