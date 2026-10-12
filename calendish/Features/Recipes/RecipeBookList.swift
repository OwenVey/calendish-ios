import SwiftUI

/// The recipe book as rows.
struct RecipeBookList: View {
    let recipes: [Recipe]
    let stats: [UUID: RecipeStats]
    let perform: (RecipeBookAction) -> Void
    @Environment(HouseholdStore.self) private var store
    @Environment(\.openRecipe) private var openRecipe

    var body: some View {
        List {
            ForEach(recipes) { recipe in
                // A button rather than a navigation link, because lists draw links with a square highlight and ignore button styles.
                Button { openRecipe(recipe) } label: {
                    // The photo's corners follow the card's, inset by the card's padding.
                    RecipeRow(recipe: recipe, showsOwner: false, stats: stats[recipe.id], artworkSize: 76,
                              artworkCornerRadius: RecipeCardButtonStyle.cornerRadius - RecipeCardButtonStyle.padding)
                }
                    // Each recipe is its own card, like the meal plan's days, with space instead of hairlines.
                    .buttonStyle(RecipeCardButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // A destructive swipe button removes the row before confirmation.
                        if store.canEdit(recipe) {
                            Button("Delete", systemImage: "trash") { perform(.delete(recipe)) }
                                .tint(.red)
                        }
                    }
                    .calendishContextMenu { RecipeContextActions(recipe: recipe, perform: perform) } preview: { RecipePreview(recipe: recipe) }
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .listRowSpacing(10)
        // Lines up with the search field above.
        .contentMargins(.horizontal, 20, for: .scrollContent)
        // The last card comes to rest above the floating tab bar.
        .contentMargins(.bottom, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(CalendishStyle.background)
    }
}
