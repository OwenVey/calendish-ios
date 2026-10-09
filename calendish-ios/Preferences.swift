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
    static let timerSound = "timerSound"

    /// Lets code outside views, such as timers, read the same defaults `@AppStorage` declares.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [defaultServings: 4, keepScreenAwake: true, showCookIngredients: true,
            cookingHaptics: true, liveActivity: true, timerSound: true])
    }

    /// Servings for a new recipe, or an imported one that doesn't say.
    static var servingsForNewRecipes: Int {
        let servings = UserDefaults.standard.integer(forKey: defaultServings)
        return servings > 0 ? servings : 4
    }
}

enum RecipeSort: String, CaseIterable, Identifiable {
    case recent, title
    var id: Self { self }
    var title: String {
        switch self {
        case .recent: "Recently Added"
        case .title: "Title A–Z"
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
