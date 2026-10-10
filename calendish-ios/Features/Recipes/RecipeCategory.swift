import Foundation

/// The meal a recipe is for. Stored by raw value, so the raw values match what's already saved.
nonisolated enum RecipeCategory: String, CaseIterable, Identifiable, Codable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", dessert = "Dessert", snack = "Snack"
    var id: Self { self }
    var title: String { rawValue }
    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "takeoutbag.and.cup.and.straw"
        case .dinner: "fork.knife"
        case .dessert: "birthday.cake"
        case .snack: "carrot"
        }
    }

    /// Matches a saved or imported label regardless of case or plural, such as "desserts". Anything else isn't a category.
    init?(matching label: String) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category = Self.allCases.first(where: {
            [$0.rawValue, $0.rawValue + "s"].contains { $0.caseInsensitiveCompare(label) == .orderedSame }
        }) else { return nil }
        self = category
    }
}
