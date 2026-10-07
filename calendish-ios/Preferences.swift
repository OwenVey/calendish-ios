import Foundation

/// Keys for on-device preferences shared by Settings and the screens they affect.
enum PreferenceKey {
    static let recipeSort = "recipeSort"
    static let groceryGrouping = "groceryGrouping"
    static let keepScreenAwake = "cookKeepScreenAwake"
    static let cookingHaptics = "cookHaptics"
    static let timerSound = "timerSound"

    /// Lets code outside views, such as timers, read the same defaults `@AppStorage` declares.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [keepScreenAwake: true, cookingHaptics: true, timerSound: true])
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

extension MealSlot {
    static let enabledStorageKey = "enabledMealSlots"
    static let allEnabled = allCases.map(\.rawValue).joined(separator: ",")

    /// The slots turned on in Settings, in breakfast–lunch–dinner order.
    static func enabled(in stored: String) -> [MealSlot] {
        let names = stored.split(separator: ",").map(String.init)
        let slots = allCases.filter { names.contains($0.rawValue) }
        return slots.isEmpty ? allCases : slots
    }

    static func storage(for slots: [MealSlot]) -> String {
        allCases.filter(slots.contains).map(\.rawValue).joined(separator: ",")
    }
}
