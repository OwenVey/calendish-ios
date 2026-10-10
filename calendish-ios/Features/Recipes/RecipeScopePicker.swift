import SwiftUI

/// Switches the recipe book between collections, such as mine and the household's.
struct RecipeScopePicker: View {
    @Binding var scope: RecipeScope

    var body: some View {
        Picker("Recipe collection", selection: $scope) {
            ForEach(RecipeScope.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
