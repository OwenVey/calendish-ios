import SwiftUI

/// The heart on a favorite recipe's photo, in the bottom-leading corner like Photos. VoiceOver hears
/// "Favorite" after the title instead, through `recipeTitleAccessibility(_:)`.
struct FavoriteBadge: View {
    var compact = false
    var body: some View {
        // A solid fill stays legible on any photo, where a translucent one disappears on dark food.
        Image(systemName: "heart.fill")
            .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(compact ? 5 : 7)
            .background(.pink, in: .circle)
            .padding(compact ? 2 : 4)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Reads "Favorite" after a favorite recipe's title, since its badge on the photo is hidden from VoiceOver.
    func recipeTitleAccessibility(_ recipe: Recipe) -> some View {
        accessibilityLabel(recipe.isFavorite ? "\(recipe.title), Favorite" : recipe.title)
    }
}
