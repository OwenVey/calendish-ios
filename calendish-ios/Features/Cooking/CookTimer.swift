import Foundation

struct CookTimer: Identifiable, Codable {
    let id: UUID
    let recipeID: UUID
    let recipeTitle: String
    let stepIndex: Int
    /// The whole length, including any added minutes.
    var duration: TimeInterval
    /// When a running timer finishes. Stale while paused.
    var end: Date
    /// Time left when the cook paused, or nil while running.
    var pausedRemaining: TimeInterval?
    /// Whether AlarmKit rings for this timer. When it does, the system alarm is the whole alert.
    var usesAlarm: Bool?
    init(recipe: Recipe, stepIndex: Int, duration: TimeInterval) {
        id = UUID()
        recipeID = recipe.id
        recipeTitle = recipe.title
        self.stepIndex = stepIndex
        self.duration = duration
        end = .now.addingTimeInterval(duration)
    }
    var durationText: String { Self.format(duration) }
    var isPaused: Bool { pausedRemaining != nil }
    /// When the timer will finish if left alone, or nil while paused.
    var deadline: Date? { isPaused ? nil : end }
    var remaining: TimeInterval { pausedRemaining ?? max(0, end.timeIntervalSinceNow) }
    /// Orders timers by when they'd finish, counting a paused timer's time left from now.
    static func soonestFirst(_ a: CookTimer, _ b: CookTimer) -> Bool { a.remaining < b.remaining }

    static func format(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    /// Finds the first time like "25 minutes" or "1-2 hrs" in a step. Ranges use the shorter time.
    static func duration(in step: String) -> TimeInterval? {
        guard let match = try? timePattern.firstMatch(in: step), let value = Double(match.output.1) else { return nil }
        switch match.output.2.lowercased().first {
        case "h": return value * 3600
        case "m": return value * 60
        default: return value
        }
    }

    /// Every time mentioned in a step, like "25 minutes" or "1-2 hrs".
    static func timeRanges(in step: String) -> [Range<String.Index>] {
        step.matches(of: timePattern).map(\.range)
    }

    private static var timePattern: Regex<(Substring, Substring, Substring)> {
        #/(\d+)\s*(?:(?:-|–|to)\s*\d+\s*)?(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/#.ignoresCase()
    }
}
