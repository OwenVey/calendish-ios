import Foundation

@main
struct GroceryImportReviewTests {
    static func recipe(_ title: String, servings: Int = 2, ingredients: [String]) -> Recipe {
        Recipe(title: title, summary: "", prepMinutes: 0, cookMinutes: 0, servings: servings,
            tags: [], symbol: "fork.knife", ingredients: ingredients.map { Ingredient(text: $0) }, steps: ["Cook"])
    }

    static func main() {
        let soup = recipe("Soup", ingredients: ["1 cup milk", "2 carrots", "Salt to taste"])
        // A deleted or edited source cannot change the ingredients imported from a saved meal.
        let planned = PlannedMeal(date: .now, recipe: soup, recipeID: soup.id, servings: 4)
        var changed = soup
        changed.ingredients = [Ingredient(text: "3 cups rice")]
        let later = PlannedMeal(date: .now, recipe: changed, recipeID: soup.id, servings: 2)
        let candidates = GroceryImportCandidate.planned([planned, later])
        precondition(candidates.count == 2 && Set(candidates.map(\.id)).count == 2)
        var plannedReview = GroceryImportReview(candidates: candidates)
        plannedReview.prepare(groceries: [], units: .original)
        let savedLines = plannedReview.sections(groceries: [], units: .original)
        precondition(savedLines[0].lines.map(\.text) == ["2 cup milk", "4 carrots", "Salt to taste"])
        precondition(savedLines[1].lines.map(\.text) == ["3 cups rice"])
        plannedReview.toggleRecipe(candidates[0].id)
        precondition(plannedReview.sections(groceries: [], units: .original)[1].allSelected,
            "Different saved versions have independent review selections")
        let salad = recipe("Salad", ingredients: ["1 cucumber"])
        let milk = GroceryItem(name: "9 cups MILK", amount: "", source: "Soup", position: 3)
        var carrots = GroceryItem(name: "2 carrots", amount: "", source: "Soup", position: 7)
        carrots.isComplete = true
        let otherSalt = GroceryItem(name: "Salt to taste", amount: "", source: "Other recipe", position: 8)
        var review = GroceryImportReview(candidates: [.init(recipe: soup, servings: 4), .init(recipe: salad, servings: 2)])
        review.prepare(groceries: [milk, carrots, otherSalt], units: .original)
        var sections = review.sections(groceries: [milk, carrots, otherSalt], units: .original)
        precondition(review.ingredientCount == 4 && review.selected.count == 3)
        precondition(sections[0].lines[0].isOnList && !sections[0].lines[0].isSelected,
            "An active item matches by food and recipe, regardless of quantity and food case")
        precondition(!sections[0].lines[1].isOnList && sections[0].lines[1].isSelected,
            "Completed groceries should be selectable again")
        precondition(!sections[0].lines[2].isOnList && sections[0].lines[2].isSelected,
            "Groceries from another recipe should not exclude an ingredient")
        precondition(sections[0].lines.map(\.text) == ["2 cup milk", "4 carrots", "Salt to taste"])

        // Reselect an existing item, deselect another, then receive a newer household snapshot.
        review.toggleIngredient(soup.ingredients[0].id)
        review.toggleIngredient(soup.ingredients[1].id)
        let newSalt = GroceryItem(name: "Salt to taste", amount: "", source: "Soup", position: 30)
        review.prepare(groceries: [newSalt], units: .original)
        sections = review.sections(groceries: [newSalt], units: .original)
        precondition(!sections[0].lines[0].isOnList && sections[0].lines[0].isSelected)
        precondition(!sections[0].lines[1].isSelected)
        precondition(sections[0].lines[2].isOnList && sections[0].lines[2].isSelected,
            "Live labels update without overriding manual selections or reseeding")

        review.setServings(2, for: soup.id)
        let metricSections = review.sections(groceries: [newSalt], units: .metric)
        precondition(metricSections[0].lines[0].text == "235 ml milk")
        let changes = review.groceriesToAdd(groceries: [newSalt], units: .metric)
        var items = changes.added
        precondition(items.map(\.name) == ["235 ml milk", "1 cucumber"] && changes.updated.isEmpty,
            "A selected line already on the list for the same recipe combines into it without changing it")
        precondition(items.map(\.position) == [31, 32], "Append after the latest snapshot in recipe and ingredient order")
        precondition(items.map(\.source) == ["Soup", "Salad"] && items.allSatisfy { $0.amount.isEmpty })
        precondition(items.map(\.name) == metricSections.flatMap(\.lines).filter(\.isSelected).map(\.text).filter { $0 != "Salt to taste" },
            "Display and output must use the same measurement preference")
        precondition(Set(items.map(\.id)).count == 2)

        review.resetServings(for: soup.id)
        precondition(review.sections(groceries: [], units: .original)[0].servings == 4,
            "Reset restores incoming planned servings, not the recipe's base servings")
        precondition(review.sections(groceries: [], units: .original)[0].lines[0].text == "2 cup milk")
        review.toggleRecipe(soup.id)
        precondition(review.sections(groceries: [], units: .original)[0].allSelected)
        review.toggleRecipe(soup.id)
        items = review.groceriesToAdd(groceries: [], units: .original).added
        precondition(items.map(\.name) == ["1 cucumber"] && items[0].position == 1,
            "Recipe selection changes should leave other recipes untouched")

        let unknown = recipe("No yield", servings: 0, ingredients: ["1 cup milk", "Salt to taste"])
        var unknownReview = GroceryImportReview(candidates: [.init(recipe: unknown, servings: 8)])
        unknownReview.prepare(groceries: [], units: .metric)
        unknownReview.setServings(10, for: unknown.id)
        let unknownSection = unknownReview.sections(groceries: [], units: .metric)[0]
        precondition(!unknownSection.canScale && unknownSection.servings == 8)
        precondition(unknownSection.lines.map(\.text) == ["235 ml milk", "Salt to taste"],
            "Unknown yield still converts measurements, without scaling")

        let emptyRecipe = recipe("Empty", ingredients: [])
        var empty = GroceryImportReview(candidates: [.init(recipe: emptyRecipe, servings: 2)])
        empty.prepare(groceries: [], units: .original)
        precondition(empty.ingredientCount == 0 && empty.selected.isEmpty)
        precondition(!empty.sections(groceries: [], units: .original)[0].allSelected)
        precondition(empty.groceriesToAdd(groceries: [], units: .original).isEmpty)

        // Two recipes that both need onions share one row that lists both.
        let stew = recipe("Stew", ingredients: ["1 large onion, diced", "1 cup unsalted butter", "2–3 carrots", "Salt to taste"])
        let tacos = recipe("Tacos", ingredients: ["2 onions, sliced", "2 tbsp. salted butter", "1 carrot", "salt"])
        let chili = recipe("Chili", ingredients: ["1 (15 oz) can beans", "2 cups stock", "1 onion"])
        var merging = GroceryImportReview(candidates: [.init(recipe: stew, servings: 2), .init(recipe: tacos, servings: 2)])
        merging.prepare(groceries: [], units: .original)
        let merged = merging.groceriesToAdd(groceries: [], units: .original).added
        precondition(merged.map(\.name) == ["3 onions", "1 cup unsalted butter", "2–3 carrots", "Salt to taste",
            "2 tbsp. salted butter", "1 carrot"], "Got \(merged.map(\.name))")
        precondition(merged[0].sources == ["Stew", "Tacos"] && merged[0].source == "Stew\nTacos")
        precondition(merged[3].sources == ["Stew", "Tacos"], "Lines without amounts combine")
        precondition(merged.map(\.position) == [1, 2, 3, 4, 5, 6])

        // A later import combines with unchecked items, but not checked ones or a different unit.
        var checked = GroceryItem(name: "2 cups stock", amount: "", source: "Soup", position: 1)
        checked.isComplete = true
        let onions = GroceryItem(name: "onions", amount: "3", source: "Stew\nTacos", position: 2)
        let beans = GroceryItem(name: "1 (28 oz) can beans", amount: "", source: "General", position: 3)
        let general = GroceryItem(name: "1 onion", amount: "", source: "General", position: 4)
        var laterReview = GroceryImportReview(candidates: [.init(recipe: chili, servings: 2)])
        laterReview.prepare(groceries: [checked, onions, beans, general], units: .original)
        let laterChanges = laterReview.groceriesToAdd(groceries: [checked, onions, beans, general], units: .original)
        precondition(laterChanges.added.map(\.name) == ["1 (15 oz) can beans", "2 cups stock"])
        precondition(laterChanges.added.map(\.position) == [5, 6])
        precondition(laterChanges.updated.count == 1)
        let update = laterChanges.updated[0]
        precondition(update.original.id == onions.id && update.item.id == onions.id)
        precondition(update.item.name == "4 onions" && update.item.amount.isEmpty, "Got \(update.item.name)")
        precondition(update.item.sources == ["Stew", "Tacos", "Chili"])

        // An item someone typed in takes on the recipe that also needs it.
        var plain = GroceryImportReview(candidates: [.init(recipe: recipe("Soup", ingredients: ["1 onion"]), servings: 2)])
        plain.prepare(groceries: [general], units: .original)
        let plainUpdate = plain.groceriesToAdd(groceries: [general], units: .original).updated
        precondition(plainUpdate.count == 1 && plainUpdate[0].item.name == "2 onions" && plainUpdate[0].item.sources == ["Soup"])
        precondition(GroceryImportReview(candidates: []).isEmpty)
        print("Grocery import review tests passed")
    }
}
