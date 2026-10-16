import SwiftUI

struct RecipeRow: View {
    let recipe: Recipe
    /// Servings to show instead of the recipe's own, such as a planned meal's.
    var servings: Int?
    /// Whether to badge the photo with whose recipe it is.
    var showsOwner = true
    /// The household's rating and cooked history, shown when there is some.
    var stats: RecipeStats?
    /// A line under the details, such as why a recipe is suggested.
    var caption: String?
    /// The photo's width and height.
    var artworkSize: CGFloat = 64
    /// The photo's corner radius, when it sits inside a card.
    var artworkCornerRadius: CGFloat?
    var body: some View {
        HStack(spacing: 14) {
            // The photo grows taller with a long title, keeping even space around it.
            RecipeArtwork(recipe: recipe, compact: true, cornerRadius: artworkCornerRadius)
                .frame(width: artworkSize)
                .frame(minHeight: artworkSize, maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) {
                    if recipe.isFavorite { FavoriteBadge(compact: true) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showsOwner { RecipeOwnerBadge(recipe: recipe, compact: true) }
                }
            VStack(alignment: .leading, spacing: 6) {
                RecipeTitle(recipe: recipe).font(.headline).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 10) {
                    if recipe.minutes > 0 {
                        Label("\(recipe.minutes) min", systemImage: "clock.fill")
                    }
                    Label(InterfaceCopy.servings(servings ?? recipe.servings), systemImage: "person.2.fill")
                    if let rating = stats?.averageRating {
                        Label(Self.formatted(rating), systemImage: "star.fill")
                            .accessibilityLabel(InterfaceCopy.rating(Self.formatted(rating)))
                    }
                }
                .labelStyle(RecipeDetailLabelStyle())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if let caption {
                    Text(caption).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        // Rows size to their details, and the photo fills that height.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
}

extension RecipeRow {
    /// An average rating like "4.5", or "4" when whole.
    static func formatted(_ rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(0...1)))
    }
}
