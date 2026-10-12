import SwiftUI

/// A recipe's photo, or its symbol on a tinted tile when it has none.
struct RecipeArtwork: View {
    let recipe: Recipe
    var compact = false
    /// Overrides the corner radius, such as to nest evenly inside a card.
    var cornerRadius: CGFloat?
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? (compact ? 14 : 24))
        ZStack {
            shape.fill(Color(.tertiarySystemFill))
            if let path = recipe.imagePath {
                RecipePhoto(path: path, thumbnail: compact)
            } else {
                Image(systemName: recipe.symbol)
                    .font(.system(size: compact ? 25 : 64, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
