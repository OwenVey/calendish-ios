import SwiftUI

/// Picks any saved recipe for a proposed dinner, including ones auto planning wouldn't suggest.
struct AutoPlanRecipePicker: View {
    let dinner: AutoPlan.Dinner
    let plan: AutoPlan
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let stats = store.recipeStats
        let recipes = store.recipes.filter { $0.matches(search) }
        NavigationStack {
            List {
                ForEach(recipes) { recipe in
                    MealRecipeChoice(recipe: recipe, stats: stats[recipe.id], isSelected: dinner.recipe?.id == recipe.id) {
                        plan.choose(recipe, for: dinner.id)
                        dismiss()
                    }
                }
                if recipes.isEmpty {
                    ContentUnavailableView(store.recipes.isEmpty ? "Add a recipe first" : "No matching recipes", systemImage: "book.closed",
                        description: Text(store.recipes.isEmpty ? "Add a recipe in Recipes, then return to plan a meal." : "Try another search."))
                }
            }
            .searchable(text: $search, prompt: "Search recipes and ingredients")
            .navigationTitle(dinner.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.toolbarGlyph() }
            }
        }
    }
}
