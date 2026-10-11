import SwiftUI

/// One checkable ingredient in cook mode's panel, highlighted when a step's mention of it was tapped.
struct CookIngredientRow: View {
    let ingredient: Ingredient
    /// The ingredient as displayed, at the current scale and units.
    let line: String
    let isChecked: Bool
    let isFocused: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? CalendishStyle.accent : Color.secondary)
                IngredientLineText(line: line, highlightsAmount: !isChecked)
                    .strikethrough(isChecked)
                    .foregroundStyle(isChecked ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.title3)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .background(isFocused ? CalendishStyle.accent.opacity(0.15) : Color.clear, in: .rect(cornerRadius: 12))
        .id(ingredient.id)
        .accessibilityIdentifier("cook-ingredient-\(ingredient.id)")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityValue(isChecked ? "Checked" : "Unchecked")
    }
}
