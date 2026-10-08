import Foundation

@main
struct GroceryImportReviewTests {
    static func recipe(_ title: String, servings: Int = 2, ingredients: [String]) -> Recipe {
        Recipe(title: title, summary: "", prepMinutes: 0, cookMinutes: 0, servings: servings,
            tags: [], symbol: "fork.knife", ingredients: ingredients.map { Ingredient(text: $0) }, steps: ["Cook"])
    }

    static func main() {
        let soup = recipe("Soup", ingredients: ["1 cup milk", "2 carrots", "Salt to taste"])
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
        var items = review.groceriesToAdd(groceries: [newSalt], units: .metric)
        precondition(items.map(\.name) == ["235 ml milk", "Salt to taste", "1 cucumber"],
            "Add honors explicit selection, even when another shopper added a matching item")
        precondition(items.map(\.position) == [31, 32, 33], "Append after the latest snapshot in recipe and ingredient order")
        precondition(items.map(\.source) == ["Soup", "Soup", "Salad"] && items.allSatisfy { $0.amount.isEmpty })
        precondition(items.map(\.name) == metricSections.flatMap(\.lines).filter(\.isSelected).map(\.text),
            "Display and output must use the same measurement preference")
        precondition(Set(items.map(\.id)).count == 3)

        review.resetServings(for: soup.id)
        precondition(review.sections(groceries: [], units: .original)[0].servings == 4,
            "Reset restores incoming planned servings, not the recipe's base servings")
        precondition(review.sections(groceries: [], units: .original)[0].lines[0].text == "2 cup milk")
        review.toggleRecipe(soup.id)
        precondition(review.sections(groceries: [], units: .original)[0].allSelected)
        review.toggleRecipe(soup.id)
        items = review.groceriesToAdd(groceries: [], units: .original)
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
        precondition(GroceryImportReview(candidates: []).isEmpty)
        print("Grocery import review tests passed")
    }
}
