import SwiftUI

/// The recipe book as a two-column grid of photos.
struct RecipeBookGrid: View {
    let recipes: [Recipe]
    let stats: [UUID: RecipeStats]
    let showsLastCooked: Bool
    @Binding var scope: RecipeScope
    let perform: (RecipeBookAction) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RecipeScopePicker(scope: $scope)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 2), spacing: 24) {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: recipe) { RecipeCard(recipe: recipe, stats: stats[recipe.id], showsLastCooked: showsLastCooked) }
                            .buttonStyle(.plain)
                            .calendishContextMenu { RecipeContextActions(recipe: recipe, perform: perform) } preview: { RecipePreview(recipe: recipe) }
                    }
                }
            }
            // Lines up with the search field above.
            .padding(.horizontal, 20)
            .padding(.bottom)
        }
        .background(CalendishStyle.background)
    }
}
