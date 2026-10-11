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
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // A destructive swipe button removes the row before confirmation.
                        if store.canEdit(recipe) {
                            Button("Delete", systemImage: "trash") { perform(.delete(recipe)) }
                                .tint(.red)
                        }
                    }
                    .calendishContextMenu { RecipeContextActions(recipe: recipe, perform: perform) } preview: { RecipePreview(recipe: recipe) }
            }
            // No hairline between the search field and the first recipe.
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
    }
}
