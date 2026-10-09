import Foundation

struct GroceryImportCandidate: Identifiable {
    var recipe: Recipe
    var servings: Int
    var id: UUID { recipe.id }

    /// Identical planned versions appear once at their largest serving count. Different saved
    /// versions get independent identities, so review choices cannot overwrite each other.
    static func planned(_ meals: [PlannedMeal]) -> [Self] {
        var candidates: [Self] = []
        var versions: [Recipe] = []
        for meal in meals {
            if let index = versions.firstIndex(where: { $0.id == meal.recipe.id && $0.hasSameVersion(as: meal.recipe) }) {
                candidates[index].servings = max(candidates[index].servings, meal.servings)
            } else {
                versions.append(meal.recipe)
                var recipe = meal.recipe
                recipe.id = meal.id
                recipe.ingredients = recipe.ingredients.map { Ingredient(text: $0.text) }
                candidates.append(Self(recipe: recipe, servings: meal.servings))
            }
        }
        return candidates
    }

    /// Notes with grocery items, each reviewed like a recipe that can't be scaled.
    static func noted(_ notes: [MealPlanNote]) -> [Self] {
        notes.filter { !$0.items.isEmpty }.map { note in
            let recipe = Recipe(id: note.id, title: note.text, summary: "", prepMinutes: 0, cookMinutes: 0, servings: 0,
                                tags: [], symbol: "", ingredients: note.items.map { Ingredient(text: $0) }, steps: [])
            return Self(recipe: recipe, servings: 0)
        }
    }
}

/// Owns review choices independently of presentation and grocery persistence.
struct GroceryImportReview {
    struct Section: Identifiable {
        struct Line: Identifiable {
            let id: UUID
            let text: String
            let isSelected: Bool
            let isOnList: Bool
        }
        let id: UUID
        let title: String
        let originalServings: Int
        let servings: Int
        let canScale: Bool
        let lines: [Line]
        var allSelected: Bool { !lines.isEmpty && lines.allSatisfy(\.isSelected) }
        var onListCount: Int { lines.filter(\.isOnList).count }
    }

    private let candidates: [GroceryImportCandidate]
    private var seeded = false
    private(set) var selected: Set<UUID> = []
    private(set) var servings: [UUID: Int] = [:]
    var ingredientCount: Int { candidates.reduce(0) { $0 + $1.recipe.ingredients.count } }
    var isEmpty: Bool { candidates.isEmpty }

    init(candidates: [GroceryImportCandidate]) {
        self.candidates = candidates
    }

    /// Only the initial list informs selection; subsequent snapshots inform labels.
    mutating func prepare(groceries: [GroceryItem], units: MeasurementPreference) {
        guard !seeded else { return }
        seeded = true
        selected = Set(sections(groceries: groceries, units: units)
            .flatMap(\.lines).filter { !$0.isOnList }.map(\.id))
    }

    mutating func toggleIngredient(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    mutating func toggleRecipe(_ id: UUID) {
        guard let candidate = candidates.first(where: { $0.id == id }) else { return }
        let ids = candidate.recipe.ingredients.map(\.id)
        if ids.allSatisfy(selected.contains) { selected.subtract(ids) }
        else { selected.formUnion(ids) }
    }

    mutating func setServings(_ count: Int, for id: UUID) {
        guard let candidate = candidates.first(where: { $0.id == id }), candidate.recipe.servings > 0 else { return }
        servings[id] = min(100, max(1, count))
    }

    mutating func resetServings(for id: UUID) { servings[id] = nil }

    func sections(groceries: [GroceryItem], units: MeasurementPreference) -> [Section] {
        candidates.map { candidate in
            let recipe = candidate.recipe
            let count = servings[candidate.id] ?? candidate.servings
            let scale = recipe.servings > 0 ? Double(count) / Double(recipe.servings) : 1
            let names = Set(groceries.filter { $0.sources.contains(recipe.title) && !$0.isComplete }.map { foodKey($0.name) })
            let lines = recipe.ingredients.map { ingredient in
                let text = ingredient.display(scale: scale, units: units)
                return Section.Line(id: ingredient.id, text: text, isSelected: selected.contains(ingredient.id),
                    isOnList: names.contains(foodKey(text)))
            }
            return Section(id: recipe.id, title: recipe.title, originalServings: candidate.servings,
                servings: count, canScale: recipe.servings > 0 && !lines.isEmpty, lines: lines)
        }
    }

    /// Use the latest grocery positions, without overriding explicit review choices. Selected lines for the same
    /// food combine with each other and with unchecked items already on the list.
    func groceriesToAdd(groceries: [GroceryItem], units: MeasurementPreference) -> GroceryImport {
        let lines = sections(groceries: groceries, units: units).flatMap { section in
            section.lines.filter(\.isSelected).map { (text: $0.text, source: section.title) }
        }
        return GroceryMerge.plan(lines, into: groceries)
    }

    private func foodKey(_ line: String) -> String {
        let name = IngredientParser.name(of: line)
        return (name.isEmpty ? line : name).lowercased()
    }
}
