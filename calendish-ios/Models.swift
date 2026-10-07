import Foundation

nonisolated struct Ingredient: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
}

struct Recipe: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var summary: String
    var minutes: Int
    var servings: Int
    var tag: String
    var symbol: String
    var ingredients: [Ingredient]
    var steps: [String]
    var isFavorite = false

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
        Recipe(title: "Lemon & herb orzo", summary: "A little sunshine in a bowl. Bright lemon, sweet tomatoes, and plenty of fresh herbs.", minutes: 25, servings: 4, tag: "Weeknight", symbol: "leaf",
               ingredients: [Ingredient(text: "1½ cups orzo"), Ingredient(text: "2 cups cherry tomatoes"), Ingredient(text: "1 lemon"), Ingredient(text: "¼ cup fresh basil"), Ingredient(text: "2 tbsp olive oil")],
               steps: ["Bring a pot of salted water to a boil. Cook the orzo until tender, then drain.", "Halve the cherry tomatoes and tear the fresh basil. Zest and juice the lemon.", "Toss the warm orzo with olive oil, tomatoes, lemon, and basil. Season to taste and serve."]),
        Recipe(title: "Roasted vegetable bowls", summary: "Colorful roasted vegetables, fluffy rice, and a creamy tahini drizzle.", minutes: 40, servings: 4, tag: "Vegetarian", symbol: "carrot",
               ingredients: [Ingredient(text: "1 cup rice"), Ingredient(text: "2 sweet potatoes"), Ingredient(text: "1 head broccoli"), Ingredient(text: "¼ cup tahini")],
               steps: ["Heat the oven to 425°F. Chop the vegetables and spread on a baking sheet.", "Roast for 25 minutes. Meanwhile, cook the rice.", "Divide rice and vegetables among bowls. Drizzle with tahini and serve."]),
        Recipe(title: "Blueberry overnight oats", summary: "An easy breakfast to wake up to, with juicy blueberries and a spoonful of yogurt.", minutes: 10, servings: 2, tag: "Breakfast", symbol: "sunrise",
               ingredients: [Ingredient(text: "1 cup rolled oats"), Ingredient(text: "1 cup oat milk"), Ingredient(text: "½ cup blueberries")],
               steps: ["Stir oats and oat milk together in two jars.", "Top with blueberries. Cover and refrigerate overnight."]),
        Recipe(title: "Crispy chickpea salad", summary: "Crunchy chickpeas, crisp greens, and a simple lemon dressing.", minutes: 30, servings: 2, tag: "Lunch", symbol: "fork.knife",
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
