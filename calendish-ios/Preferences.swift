import Foundation

/// Keys for on-device preferences shared by Settings and the screens they affect.
nonisolated enum PreferenceKey {
    static let recipeSort = "recipeSort"
    static let recipeLayout = "recipeLayout"
    static let defaultServings = "defaultServings"
    static let groceryGrouping = "groceryGrouping"
    static let showCompletedGroceries = "showCompletedGroceries"
    static let keepScreenAwake = "cookKeepScreenAwake"
    static let showCookIngredients = "cookShowIngredients"
    static let cookingHaptics = "cookHaptics"
    static let liveActivity = "cookLiveActivity"
    /// Whether the voice-commands explanation has been shown before first activation.
    static let handsFreeIntroSeen = "cookHandsFreeIntroSeen"
    static let timerAlert = "timerAlert"
    static let groceryAutoClear = "groceryAutoClear"

    /// Lets code outside views, such as timers, read the same defaults `@AppStorage` declares.
    static func registerDefaults() {
        let defaults = UserDefaults.standard
        // Timer sound used to be an on/off switch. Keep timers silent for anyone who turned it off.
        if let soundOn = defaults.object(forKey: "timerSound") as? Bool {
            if !soundOn, defaults.object(forKey: timerAlert) == nil { defaults.set(TimerAlert.silent.rawValue, forKey: timerAlert) }
            defaults.removeObject(forKey: "timerSound")
        }
        defaults.register(defaults: [defaultServings: 4, keepScreenAwake: true, showCookIngredients: true,
            cookingHaptics: true, liveActivity: true, timerAlert: TimerAlert.alarm.rawValue])
    }

    /// Servings for a new recipe, or an imported one that doesn't say.
    static var servingsForNewRecipes: Int {
        let servings = UserDefaults.standard.integer(forKey: defaultServings)
        return servings > 0 ? servings : 4
    }
}

enum RecipeSort: String, CaseIterable, Identifiable {
    case recent, title, rating, recentlyCooked, leastRecentlyCooked
    var id: Self { self }
    var title: String {
        switch self {
        case .recent: "Recently Added"
        case .title: "Title A–Z"
        case .rating: "Highest Rated"
        case .recentlyCooked: "Recently Cooked"
        case .leastRecentlyCooked: "Least Recently Cooked"
        }
    }
    var showsLastCooked: Bool { self == .recentlyCooked || self == .leastRecentlyCooked }

    /// Sorts recipes already in Recently Added order. Ties keep that order; never-cooked recipes count as
    /// cooked longest ago, and unrated recipes come after rated ones.
    func sorted(_ recipes: [Recipe], stats: [UUID: RecipeStats]) -> [Recipe] {
        switch self {
        case .recent: return recipes
        case .title: return recipes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .rating:
            return recipes.enumerated().sorted { a, b in
                let ra = stats[a.element.id]?.averageRating ?? 0, rb = stats[b.element.id]?.averageRating ?? 0
                return ra != rb ? ra > rb : a.offset < b.offset
            }.map(\.element)
        case .recentlyCooked, .leastRecentlyCooked:
            return recipes.enumerated().sorted { a, b in
                let da = stats[a.element.id]?.history.lastCooked ?? .distantPast, db = stats[b.element.id]?.history.lastCooked ?? .distantPast
                guard da != db else { return a.offset < b.offset }
                return self == .recentlyCooked ? da > db : da < db
            }.map(\.element)
        }
    }
}

enum RecipeLayout: String, CaseIterable, Identifiable {
    case list, grid
    var id: Self { self }
    var title: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

/// How long checked-off groceries stay on the list before they're removed for the whole household.
enum GroceryAutoClear: String, CaseIterable, Identifiable {
    case never, hour, day, week
    var id: Self { self }
    var title: String {
        switch self {
        case .never: "Never"
        case .hour: "After an Hour"
        case .day: "After a Day"
        case .week: "After a Week"
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
    static var current: GroceryAutoClear {
        UserDefaults.standard.string(forKey: PreferenceKey.groceryAutoClear).flatMap(GroceryAutoClear.init) ?? .never
    }
}

/// How a finished cooking timer gets your attention.
nonisolated enum TimerAlert: String, CaseIterable, Identifiable {
    /// Rings through AlarmKit, like a Clock app timer, even in silent mode or a Focus.
    case alarm
    case notification
    case silent
    var id: Self { self }
    var title: String {
        switch self {
        case .alarm: "Alarm"
        case .notification: "Notification"
        case .silent: "Silent"
        }
    }
    static var current: TimerAlert {
        UserDefaults.standard.string(forKey: PreferenceKey.timerAlert).flatMap(TimerAlert.init) ?? .alarm
    }
}
