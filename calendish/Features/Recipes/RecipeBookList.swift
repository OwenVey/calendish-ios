import SwiftUI

/// The recipe book as rows.
struct RecipeBookList: View {
    let recipes: [Recipe]
    let stats: [UUID: RecipeStats]
    let perform: (RecipeBookAction) -> Void
    @Environment(HouseholdStore.self) private var store

    var body: some View {
        List {
            ForEach(recipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeRow(recipe: recipe, showsOwner: false, stats: stats[recipe.id], artworkSize: 76)
                }
                    // Photo rows read as tappable without a chevron, and the title gets the width.
                    .navigationLinkIndicatorVisibility(.hidden)
                    // Each recipe is its own card, like the meal plan's days, with space instead of hairlines.
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(CalendishStyle.surface))
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
        .scrollContentBackground(.hidden)
        .background(CalendishStyle.background)
    }
}
