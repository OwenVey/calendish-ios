import SwiftUI

/// A recipe's photo with its title and time below, for the recipe book's grid.
struct RecipeCard: View {
    let recipe: Recipe
    var stats: RecipeStats?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeArtwork(recipe: recipe, thumbnail: true)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    if recipe.isFavorite { FavoriteBadge() }
                }
                .overlay(alignment: .bottomTrailing) { RecipeOwnerBadge(recipe: recipe) }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.headline).lineLimit(2).recipeTitleAccessibility(recipe)
                HStack(spacing: 4) {
                    if recipe.minutes > 0 {
                        Image(systemName: "clock").font(.caption2).accessibilityHidden(true)
                        Text("\(recipe.minutes) min")
                    }
                    if let rating = stats?.averageRating {
                        Image(systemName: "star.fill").font(.caption2).padding(.leading, 4).accessibilityHidden(true)
                        Text(RecipeRow.formatted(rating)).accessibilityLabel(InterfaceCopy.rating(RecipeRow.formatted(rating)))
                    }
                    RecipePrivateIcon(recipe: recipe).font(.caption2).padding(.leading, 4)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(.rect)
    }
}
