import SwiftUI

/// A recipe to choose when planning a meal, checked when selected.
struct MealRecipeChoice: View {
    let recipe: Recipe
    let stats: RecipeStats?
    var caption: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                RecipeRow(recipe: recipe, stats: stats, caption: caption)
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(CalendishStyle.accent).accessibilityHidden(true) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
