import Foundation

nonisolated struct Ingredient: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String

    /// The ingredient with its leading quantity, or range like "2–3", multiplied by `factor`.
    /// Lines without a recognizable quantity, such as "Salt to taste", stay as written.
    func scaled(by factor: Double) -> String { Ingredient.scale(text, by: factor) }

    static func scale(_ text: String, by factor: Double) -> String {
        guard factor != 1, factor > 0,
              let match = text.firstMatch(of: #/^(\s*)(\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:[.,]\d+)?(?:\s?[¼½¾⅓⅔⅛⅜⅝⅞])?|[¼½¾⅓⅔⅛⅜⅝⅞])(?:(\s*[-–]\s*|\s+to\s+)(\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:[.,]\d+)?(?:\s?[¼½¾⅓⅔⅛⅜⅝⅞])?|[¼½¾⅓⅔⅛⅜⅝⅞]))?(?=\s|\(|\p{L}|$)/#),
              let low = quantity(String(match.output.2)) else { return text }
        let usesDecimals = match.output.2.contains { $0 == "." || $0 == "," }
        var result = String(match.output.1) + format(low * factor, decimals: usesDecimals)
        if let separator = match.output.3, let highText = match.output.4 {
            guard let high = quantity(String(highText)) else { return text }
            result += separator + format(high * factor, decimals: usesDecimals || highText.contains { $0 == "." || $0 == "," })
        }
        return result + text[match.range.upperBound...]
    }

    private static let fractionGlyphs: [(Character, Double)] = [
        ("⅛", 0.125), ("¼", 0.25), ("⅓", 1.0 / 3), ("⅜", 0.375), ("½", 0.5), ("⅝", 0.625), ("⅔", 2.0 / 3), ("¾", 0.75), ("⅞", 0.875)
    ]

    private static func quantity(_ token: String) -> Double? {
        var token = token.replacingOccurrences(of: ",", with: ".")
        var total = 0.0
        if let last = token.last, let glyph = fractionGlyphs.first(where: { $0.0 == last }) {
            total += glyph.1
            token = String(token.dropLast()).trimmingCharacters(in: .whitespaces)
            if token.isEmpty { return total }
        }
        let parts = token.split(separator: " ")
        for part in parts {
            if part.contains("/") {
                let pieces = part.split(separator: "/")
                guard pieces.count == 2, let numerator = Double(pieces[0]), let denominator = Double(pieces[1]), denominator > 0 else { return nil }
                total += numerator / denominator
            } else {
                guard let whole = Double(part) else { return nil }
                total += whole
            }
        }
        return total
    }

    /// Kitchen-friendly numbers: "1½" rather than "1.5", unless the recipe wrote decimals itself.
    private static func format(_ value: Double, decimals: Bool) -> String {
        if !decimals {
            let whole = value.rounded(.down)
            let remainder = value - whole
            if remainder < 0.03 { return whole.formatted(.number.precision(.fractionLength(0))) }
            if remainder > 0.97 { return (whole + 1).formatted(.number.precision(.fractionLength(0))) }
            if let glyph = fractionGlyphs.first(where: { abs($0.1 - remainder) < 0.03 }) {
                return (whole > 0 ? whole.formatted(.number.precision(.fractionLength(0))) : "") + String(glyph.0)
            }
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct Recipe: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var summary: String
    var prepMinutes: Int
    var cookMinutes: Int
    var minutes: Int { prepMinutes + cookMinutes }
    var servings: Int
    var tags: [String]
    var symbol: String
    var ingredients: [Ingredient]
    var steps: [String]
    var isFavorite = false
    /// Where the photo lives in the `recipe-images` bucket, or nil when there's no photo.
    var imagePath: String?
    var recipeLink: String?
    /// The kind of dish, such as "Dinner" or "Dessert", kept apart from free-form tags.
    var category: String?
    /// What the recipe makes when that isn't just servings, such as "24 cookies".
    var yieldText: String?

    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        }
    }
}

struct PlannedMeal: Identifiable {
    var id = UUID()
    var date: Date
    var slot: MealSlot
    var recipeID: UUID
    var servings: Int
}

struct GroceryItem: Identifiable {
    var id = UUID()
    var name: String
    var amount: String
    var source: String
    var isComplete = false
    var position: Double = 0
}

struct Household: Identifiable {
    var id: UUID
    var name: String
    var inviteCode: String
}

struct HouseholdMember: Identifiable {
    var userID: UUID
    var displayName: String
    var role: String
    var avatarURL: URL?
    var id: UUID { userID }
}

enum SampleRecipes {
    static let all: [Recipe] = [
        Recipe(title: "Lemon & herb orzo", summary: "A little sunshine in a bowl. Bright lemon, sweet tomatoes, and plenty of fresh herbs.", prepMinutes: 10, cookMinutes: 15, servings: 4, tags: ["Weeknight", "Vegetarian"], symbol: "leaf",
               ingredients: [Ingredient(text: "1½ cups orzo"), Ingredient(text: "2 cups cherry tomatoes"), Ingredient(text: "1 lemon"), Ingredient(text: "¼ cup fresh basil"), Ingredient(text: "2 tbsp olive oil")],
               steps: ["Bring a pot of salted water to a boil. Cook the orzo until tender, then drain.", "Halve the cherry tomatoes and tear the fresh basil. Zest and juice the lemon.", "Toss the warm orzo with olive oil, tomatoes, lemon, and basil. Season to taste and serve."]),
        Recipe(title: "Roasted vegetable bowls", summary: "Colorful roasted vegetables, fluffy rice, and a creamy tahini drizzle.", prepMinutes: 15, cookMinutes: 25, servings: 4, tags: ["Vegetarian"], symbol: "carrot",
               ingredients: [Ingredient(text: "1 cup rice"), Ingredient(text: "2 sweet potatoes"), Ingredient(text: "1 head broccoli"), Ingredient(text: "¼ cup tahini")],
               steps: ["Heat the oven to 425°F. Chop the vegetables and spread on a baking sheet.", "Roast for 25 minutes. Meanwhile, cook the rice.", "Divide rice and vegetables among bowls. Drizzle with tahini and serve."]),
        Recipe(title: "Blueberry overnight oats", summary: "An easy breakfast to wake up to, with juicy blueberries and a spoonful of yogurt.", prepMinutes: 10, cookMinutes: 0, servings: 2, tags: ["Breakfast", "Make ahead"], symbol: "sunrise",
               ingredients: [Ingredient(text: "1 cup rolled oats"), Ingredient(text: "1 cup oat milk"), Ingredient(text: "½ cup blueberries")],
               steps: ["Stir oats and oat milk together in two jars.", "Top with blueberries. Cover and refrigerate overnight."]),
        Recipe(title: "Crispy chickpea salad", summary: "Crunchy chickpeas, crisp greens, and a simple lemon dressing.", prepMinutes: 10, cookMinutes: 20, servings: 2, tags: ["Lunch"], symbol: "fork.knife",
               ingredients: [Ingredient(text: "1 can chickpeas"), Ingredient(text: "4 cups mixed greens"), Ingredient(text: "1 lemon")],
               steps: ["Drain and dry the chickpeas. Roast at 425°F until crisp.", "Toss the greens with lemon dressing and top with the warm chickpeas."])
    ]
}

enum CalendarDays {
    static func startOfWeek(_ date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let offset = calendar.component(.weekday, from: day) - 1
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    static func week(containing date: Date) -> [Date] {
        let start = startOfWeek(date)
        return (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
    }

    /// Two years of weeks on either side of today, for the swipeable week strip.
    static let plannableWeeks: [Date] = {
        let thisWeek = startOfWeek(.now)
        return (-104...104).map { Calendar.current.date(byAdding: .weekOfYear, value: $0, to: thisWeek)! }
    }()
    static var plannableRange: ClosedRange<Date> {
        plannableWeeks.first!...Calendar.current.date(byAdding: .day, value: 6, to: plannableWeeks.last!)!
    }
}
