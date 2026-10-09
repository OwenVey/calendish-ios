import Foundation

/// A day a member recorded a recipe as cooked, by hand or by finishing Cook Mode.
struct RecipeCook: Hashable {
    var recipeID: UUID
    var date: Date
    var cookedBy: UUID?
}

/// One day in a recipe's cooked history, and how it got there. A day can be both marked and a past planned meal.
struct CookedDay: Hashable {
    var date: Date
    /// Recorded by a member. Only marked days can be removed; removing one leaves any planned meal that day.
    var isMarked: Bool
    /// A past planned meal of the recipe, which leaves the history only when removed from the meal plan.
    var isPlanned: Bool
}

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

    /// "Last cooked 3 weeks ago", or "Not cooked yet".
    static func lastCookedText(_ history: CookedHistory?, now: Date = .now) -> String {
        history?.lastCooked.map { "Last cooked \(cookedAgo($0, now: now))" } ?? "Not cooked yet"
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

/// A cook finished in Cook Mode, waiting to become a marked cook.
struct FinishedCook: Codable, Hashable {
    var recipeID: UUID
    /// The day cooking started, so a late dinner finished after midnight counts for its evening.
    var day: Date
    var accountID: UUID?

    init(recipeID: UUID, startedAt: Date, accountID: UUID?) {
        self.recipeID = recipeID
        day = Calendar.current.startOfDay(for: startedAt)
        self.accountID = accountID
    }
}

/// Finished cooks waiting for the household to record them. They're kept on the device because the Live Activity
/// can finish a cook while the app runs in the background, before the household has loaded.
final class FinishedCooks {
    static let shared = FinishedCooks()
    private let defaults: UserDefaults
    private let storageKey = "finishedCooks"
    private var recorder: (accountID: UUID, record: (FinishedCook) -> Void)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Cooks not yet recorded, oldest first.
    var pending: [FinishedCook] {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([FinishedCook].self, from: $0) } ?? []
    }

    func add(_ cook: FinishedCook) {
        save(pending + [cook])
        drain()
    }

    /// Records waiting cooks, then later ones as they finish, for an account's household.
    /// Cooks finished under another account are dropped rather than recorded for the wrong household.
    func record(for accountID: UUID, with record: @escaping (FinishedCook) -> Void) {
        recorder = (accountID, record)
        drain()
    }

    /// Keeps finished cooks waiting until a household loads again.
    func stopRecording() { recorder = nil }

    private func drain() {
        guard let recorder else { return }
        let cooks = pending
        guard !cooks.isEmpty else { return }
        save([])
        for cook in cooks where cook.accountID == recorder.accountID { recorder.record(cook) }
    }

    private func save(_ cooks: [FinishedCook]) {
        if cooks.isEmpty { defaults.removeObject(forKey: storageKey) }
        else { defaults.set(try? JSONEncoder().encode(cooks), forKey: storageKey) }
    }
}
