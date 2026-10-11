import SwiftUI

struct RecipeRow: View {
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    /// Servings to show instead of the recipe's own, such as a planned meal's.
    var servings: Int?
    /// Whether to name whose recipe it is.
    var showsOwner = true
    /// The household's rating and cooked history, shown when there is some.
    var stats: RecipeStats?
    /// A line under the details, such as why a recipe is suggested.
    var caption: String?
    /// The photo's width and height.
    var artworkSize: CGFloat = 64
    /// Whose recipe it is. Your own recipes don't name an owner.
    private var owner: String? { !showsOwner || store.isMine(recipe) ? nil : store.ownerName(of: recipe) }
    var body: some View {
        HStack(spacing: 14) {
            RecipeArtwork(recipe: recipe, compact: true).frame(width: artworkSize, height: artworkSize)
                .overlay(alignment: .bottomLeading) {
                    if recipe.isFavorite { FavoriteBadge(compact: true) }
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(recipe.title).font(.headline).foregroundStyle(.primary).lineLimit(2).recipeTitleAccessibility(recipe)
                    if store.isMine(recipe), recipe.owner?.isShared == false {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Only me")
                    }
                }
                if let owner {
                    Text(recipe.owner?.person == nil ? "Owned by the household" : "\(owner)’s recipe").font(.footnote).foregroundStyle(.secondary).lineLimit(1).padding(.top, -4)
                }
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
                if !recipe.tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(recipe.tags.prefix(2), id: \.self) { TagPill(tag: $0, compact: true) }
                        if recipe.tags.count > 2 {
                            Text("+\(recipe.tags.count - 2)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.vertical, 4)
        }
    }
}

extension RecipeRow {
    /// An average rating like "4.5", or "4" when whole.
    static func formatted(_ rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(0...1)))
    }
}
