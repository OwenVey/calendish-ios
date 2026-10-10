import SwiftUI

/// A recipe's photo and details, shown when pressing and holding it in the recipe book.
struct RecipePreview: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecipeArtwork(recipe: recipe).aspectRatio(4 / 3, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title).font(.title3.weight(.semibold))
                if !recipe.summary.isEmpty {
                    Text(recipe.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 320)
    }
}
