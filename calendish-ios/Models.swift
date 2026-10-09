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

    /// The value of a quantity token such as "1½", "1 1/2", or "1.5".
    static func quantity(_ token: String) -> Double? {
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
    static func format(_ value: Double, decimals: Bool) -> String {
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

/// How recipe quantities and temperatures are shown. Saved recipes always keep the text as written.
nonisolated enum MeasurementPreference: String, CaseIterable, Identifiable, Sendable {
    case original, us, metric
    static let storageKey = "measurementUnits"
    var id: Self { self }
    var title: String {
        switch self {
        case .original: "As Written"
        case .us: "US"
        case .metric: "Metric"
        }
    }
    static var current: MeasurementPreference {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MeasurementPreference.init) ?? .original
    }
}

extension Ingredient {
    /// The ingredient scaled by `factor`, then converted to `units`.
    func display(scale factor: Double, units: MeasurementPreference) -> String {
        Ingredient.convert(Ingredient.scale(text, by: factor), to: units)
    }

    private enum Dimension { case volume, mass }
    /// `base` is milliliters for volume and grams for mass.
    private struct MeasureUnit {
        let names: [String]
        let dimension: Dimension
        let base: Double
        let isMetric: Bool
    }

    /// Teaspoons and tablespoons stay as written in both systems; metric kitchens use them too.
    private static let measureUnits: [MeasureUnit] = [
        MeasureUnit(names: ["fluid ounces", "fluid ounce", "fl. oz", "fl oz"], dimension: .volume, base: 29.5735, isMetric: false),
        MeasureUnit(names: ["cups", "cup", "c."], dimension: .volume, base: 236.588, isMetric: false),
        MeasureUnit(names: ["pints", "pint", "pt"], dimension: .volume, base: 473.176, isMetric: false),
        MeasureUnit(names: ["quarts", "quart", "qt"], dimension: .volume, base: 946.353, isMetric: false),
        MeasureUnit(names: ["gallons", "gallon", "gal"], dimension: .volume, base: 3785.41, isMetric: false),
        MeasureUnit(names: ["ounces", "ounce", "oz"], dimension: .mass, base: 28.3495, isMetric: false),
        MeasureUnit(names: ["pounds", "pound", "lbs", "lb"], dimension: .mass, base: 453.592, isMetric: false),
        MeasureUnit(names: ["milliliters", "millilitres", "milliliter", "millilitre", "ml"], dimension: .volume, base: 1, isMetric: true),
        MeasureUnit(names: ["liters", "litres", "liter", "litre", "l"], dimension: .volume, base: 1000, isMetric: true),
        MeasureUnit(names: ["dl"], dimension: .volume, base: 100, isMetric: true),
        MeasureUnit(names: ["cl"], dimension: .volume, base: 10, isMetric: true),
        MeasureUnit(names: ["kilograms", "kilogram", "kilos", "kilo", "kg"], dimension: .mass, base: 1000, isMetric: true),
        MeasureUnit(names: ["grams", "gram", "g"], dimension: .mass, base: 1, isMetric: true),
    ]

    /// Converts a leading quantity and unit, such as "2 cups" or "1–2 lb", to the other measurement system.
    /// Lines in the requested system, or without a recognizable unit, stay as written.
    static func convert(_ text: String, to units: MeasurementPreference) -> String {
        guard units != .original,
              let match = text.firstMatch(of: #/^(\s*)(\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:[.,]\d+)?(?:\s?[¼½¾⅓⅔⅛⅜⅝⅞])?|[¼½¾⅓⅔⅛⅜⅝⅞])(?:(\s*[-–]\s*|\s+to\s+)(\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:[.,]\d+)?(?:\s?[¼½¾⅓⅔⅛⅜⅝⅞])?|[¼½¾⅓⅔⅛⅜⅝⅞]))?/#),
              let low = quantity(String(match.output.2)) else { return text }
        let high = match.output.4.flatMap { quantity(String($0)) }
        guard match.output.4 == nil || high != nil else { return text }
        let afterQuantity = text[match.range.upperBound...].drop { $0 == " " }
        guard let (unit, length) = measureUnit(at: afterQuantity), unit.isMetric == (units == .us) else { return text }
        let target = targetUnit(unit.dimension, amount: low * unit.base, metric: units == .metric)
        let convert = { (value: Double) in round(value * unit.base / target.base, step: target.step) }
        let lowValue = convert(low)
        var result = String(match.output.1) + format(lowValue, decimals: units == .metric)
        var largest = lowValue
        if let high, let separator = match.output.3 {
            let highValue = convert(high)
            largest = highValue
            result += separator + format(highValue, decimals: units == .metric)
        }
        let label = largest > 1 ? target.plural : target.singular
        return result + " " + label + afterQuantity.dropFirst(length)
    }

    /// The unit at the start of `text`, with how many characters it spans. Units must end at a word boundary.
    private static func measureUnit(at text: Substring) -> (MeasureUnit, Int)? {
        let candidates = measureUnits.flatMap { unit in unit.names.map { (unit, $0) } }.sorted { $0.1.count > $1.1.count }
        for (unit, name) in candidates {
            guard text.lowercased().hasPrefix(name) else { continue }
            var rest = text.dropFirst(name.count)
            if let next = rest.first, next.isLetter { continue }
            var length = name.count
            // Abbreviations like "oz." or "lb." absorb their period.
            if name.count <= 3, !name.hasSuffix("."), rest.first == ".", rest.dropFirst().first?.isLetter != true {
                length += 1
                rest = rest.dropFirst()
            }
            return (unit, length)
        }
        return nil
    }

    private struct TargetUnit {
        let singular: String
        let plural: String
        let base: Double
        let step: Double
    }

    private static func targetUnit(_ dimension: Dimension, amount: Double, metric: Bool) -> TargetUnit {
        switch (dimension, metric) {
        case (.volume, true):
            amount >= 1000 ? TargetUnit(singular: "L", plural: "L", base: 1000, step: 0.05)
                : TargetUnit(singular: "ml", plural: "ml", base: 1, step: amount >= 20 ? 5 : 1)
        case (.mass, true):
            amount >= 1000 ? TargetUnit(singular: "kg", plural: "kg", base: 1000, step: 0.05)
                : TargetUnit(singular: "g", plural: "g", base: 1, step: amount >= 100 ? 5 : 1)
        case (.volume, false):
            amount < 14 ? TargetUnit(singular: "tsp", plural: "tsp", base: 4.92892, step: 0)
                : amount < 59 ? TargetUnit(singular: "tbsp", plural: "tbsp", base: 14.7868, step: 0)
                : TargetUnit(singular: "cup", plural: "cups", base: 236.588, step: 0)
        case (.mass, false):
            amount >= 453 ? TargetUnit(singular: "lb", plural: "lb", base: 453.592, step: 0.25)
                : TargetUnit(singular: "oz", plural: "oz", base: 28.3495, step: 0.25)
        }
    }

    /// Values round to a step when there is one; otherwise to the nearest kitchen fraction, including thirds.
    private static func round(_ value: Double, step: Double) -> Double {
        if step > 0 { return max(step, (value / step).rounded() * step) }
        let fractions = [0, 0.125, 0.25, 1.0 / 3, 0.375, 0.5, 0.625, 2.0 / 3, 0.75, 0.875, 1]
        let whole = value.rounded(.down)
        let nearest = fractions.min { abs(whole + $0 - value) < abs(whole + $1 - value) }!
        return max(0.125, whole + nearest)
    }

    /// Converts oven and food temperatures such as "425°F" or "180 degrees C" to the other scale.
    static func convertTemperatures(in text: String, to units: MeasurementPreference) -> String {
        guard units != .original else { return text }
        let pattern = #/(\d+)\s*(?:°|º|degrees?\s+)\s*([fc])(?:ahrenheit|elsius)?\b/#.ignoresCase()
        return text.replacing(pattern) { match in
            guard let value = Double(match.output.1) else { return String(match.output.0) }
            let isFahrenheit = match.output.2.lowercased() == "f"
            switch (isFahrenheit, units) {
            case (true, .metric):
                let celsius = (value - 32) * 5 / 9
                let step = celsius >= 100 ? 10.0 : 1
                return "\(Int((celsius / step).rounded() * step))°C"
            case (false, .us):
                let fahrenheit = value * 9 / 5 + 32
                let step = fahrenheit >= 200 ? 25.0 : 1
                return "\(Int((fahrenheit / step).rounded() * step))°F"
            default:
                return String(match.output.0)
            }
        }
    }
}

struct Recipe: Identifiable, Hashable, Codable {
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
    /// The kind of dish, kept apart from free-form tags.
    var category: RecipeCategory?
    /// What the recipe makes when that isn't just servings, such as "24 cookies".
    var yieldText: String?
    /// Who the recipe belongs to. Nil for a planned meal's saved version.
    var owner: RecipeOwner?

    // Keep synthesized value equality: Observation compares recipe arrays before
    // notifying views. ID-only equality hides edits to an existing recipe.

    /// Whether two recipes have the same cooking content, ignoring who owns or favorited them.
    func hasSameVersion(as other: Recipe) -> Bool {
        var mine = self, theirs = other
        mine.owner = nil; theirs.owner = nil
        mine.isFavorite = false; theirs.isFavorite = false
        mine.id = theirs.id
        return mine == theirs
    }
}

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

/// A personal recipe belongs to a person and follows them between households; sharing lets their
/// household use the same original. A household recipe belongs to the household, and every member edits it.
enum RecipeOwner: Hashable, Codable {
    case person(UUID, shared: Bool)
    case household

    var person: UUID? { if case .person(let id, _) = self { id } else { nil } }
    var isShared: Bool { if case .person(_, let shared) = self { shared } else { false } }
}

/// The Recipes browser's ownership filters. Mine and Household overlap for a recipe the person shares.
enum RecipeScope: String, CaseIterable, Identifiable {
    case all, mine, household
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .mine: "Mine"
        case .household: "Household"
        }
    }

    func includes(_ recipe: Recipe, person: UUID?) -> Bool {
        switch (self, recipe.owner) {
        case (.all, _): true
        case (.mine, .person(let owner, _)?): owner == person
        case (.household, .household?): true
        case (.household, .person(_, let shared)?): shared
        default: false
        }
    }
}

struct PlannedMeal: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    /// The recipe as it was when planned. Later edits or deletion of the source don't change it.
    var recipe: Recipe
    /// The source recipe, while it still exists, for an explicit update to its latest version.
    var recipeID: UUID?
    var servings: Int

    init(id: UUID = UUID(), date: Date, recipe: Recipe, recipeID: UUID?, servings: Int) {
        self.id = id
        self.date = date
        var saved = recipe
        saved.owner = nil
        saved.isFavorite = false
        self.recipe = saved
        self.recipeID = recipeID
        self.servings = servings
    }
}

/// A plan for a day that isn't a recipe, such as "Leftovers" or "Dinner at Mom's", with any groceries it needs.
struct MealPlanNote: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    /// Grocery items to add with the day's meals, such as "Baguette".
    var items: [String] = []
}

/// One person's rating and note for a recipe, such as four stars and "Use half the salt". The household sees each member's.
struct RecipeReview: Hashable {
    var userID: UUID
    var recipeID: UUID
    /// One to five stars, or nil when the person only left a note.
    var rating: Int?
    var note: String = ""
    var isEmpty: Bool { rating == nil && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct GroceryItem: Identifiable {
    var id = UUID()
    var name: String
    var amount: String
    var source: String
    var isComplete = false
    var position: Double = 0
    /// A `GroceryAisle` raw value, or nil until the item has been sorted.
    var aisle: String?

    /// The recipes this item is for. An item merged from several recipes stores each title on its own line of `source`.
    var sources: [String] {
        get { source.split(separator: "\n").map(String.init) }
        set { source = newValue.joined(separator: "\n") }
    }
}

struct Household: Identifiable {
    var id: UUID
    var name: String
    var inviteCode: String
    /// A link that opens Calendish and offers to join this household.
    var inviteLink: URL { HouseholdInvite.link(for: inviteCode) }
}

/// Household invitations travel as `calendish://join/<code>` links or as the bare code.
nonisolated enum HouseholdInvite {
    static func link(for code: String) -> URL { URL(string: "calendish://join/\(code)")! }

    /// The invite code in a join link, or nil for any other URL.
    static func code(from url: URL) -> String? {
        guard url.scheme == "calendish", url.host == "join" else { return nil }
        let code = url.pathComponents.dropFirst().first
            ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
        return code.map(normalized).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
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

/// The first day of the meal plan's week. Raw values match `Calendar` weekday numbers; zero follows the region.
enum WeekStart: Int, CaseIterable, Identifiable {
    case system = 0, sunday = 1, monday = 2, saturday = 7
    static let storageKey = "weekStart"
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "System"
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .saturday: "Saturday"
        }
    }
    var weekday: Int { self == .system ? Calendar.current.firstWeekday : rawValue }
    /// The current calendar starting weeks on this day, for date pickers.
    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekday
        return calendar
    }
    static var current: WeekStart { WeekStart(rawValue: UserDefaults.standard.integer(forKey: storageKey)) ?? .system }
}

enum CalendarDays {
    static func startOfWeek(_ date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - WeekStart.current.weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    static func week(containing date: Date) -> [Date] {
        let start = startOfWeek(date)
        return (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
    }
}
