import SwiftUI

/// Scales a recipe page's ingredients. Once scaled, tapping the servings count goes back to the recipe as written.
struct RecipeServingsStepper: View {
    /// Servings the ingredients are shown for.
    let servings: Int
    /// The recipe's own servings.
    let recipeServings: Int
    /// Servings the cook scaled to, or nil to use the recipe as written.
    @Binding var scaledServings: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isScaled: Bool { servings != recipeServings && recipeServings > 0 }

    var body: some View {
        HStack(spacing: 10) {
            // Tinted once scaled; tapping the count goes back to the recipe as written.
            Button { scaledServings = nil } label: {
                Text(InterfaceCopy.servings(servings)).monospacedDigit().contentTransition(.numericText(value: Double(servings)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isScaled ? CalendishStyle.accent : Color.secondary)
            .allowsHitTesting(isScaled)
            .accessibilityHidden(!isScaled)
            .accessibilityLabel("Reset to \(InterfaceCopy.servings(recipeServings))")
            Stepper("Servings", value: Binding(get: { servings }, set: { scaledServings = $0 }), in: 1...100)
                .labelsHidden()
                .accessibilityValue(InterfaceCopy.servings(servings))
        }
        .font(.subheadline)
        .fixedSize()
        .animation(reduceMotion ? nil : .snappy, value: servings)
        .hapticFeedback(.selection, trigger: servings)
    }
}
