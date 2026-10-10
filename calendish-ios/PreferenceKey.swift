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
