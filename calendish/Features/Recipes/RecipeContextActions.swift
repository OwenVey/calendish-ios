import SwiftUI

/// A recipe's context menu in the recipe book. Favoriting happens here; other actions go to the book.
struct RecipeContextActions: View {
    let recipe: Recipe
    let perform: (RecipeBookAction) -> Void
    @Environment(HouseholdStore.self) private var store

    var body: some View {
        Section {
            Button("Plan a meal", systemImage: "calendar.badge.plus") { perform(.plan(recipe)) }
            Button("Add to groceries", systemImage: "basket") { perform(.addToGroceries(recipe)) }
        }
        Section {
            Button(recipe.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: recipe.isFavorite ? "star.slash" : "star") {
                store.toggleFavorite(recipe)
            }
        }
        if store.canEdit(recipe) {
            Section {
                Button("Delete recipe", systemImage: "trash", role: .destructive) { perform(.delete(recipe)) }
            }
        }
    }
}
