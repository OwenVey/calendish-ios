import SwiftUI

/// A link that was already imported, offering the saved recipe before importing it again.
struct RecipeImportDuplicate: View {
    let recipe: Recipe
    let onOpen: () -> Void
    let onImportAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Already in your recipes", systemImage: "book.closed")
        } description: {
            Text("“\(recipe.title)” was imported from this link.")
        } actions: {
            Button("Open recipe", action: onOpen)
                .modifier(GlassActionStyle(prominent: true))
            Button("Import again", action: onImportAgain)
        }
    }
}
