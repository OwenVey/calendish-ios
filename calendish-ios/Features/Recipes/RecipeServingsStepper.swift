import SwiftUI

/// Scales a recipe page's ingredients, with a way back to the recipe as written.
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
        HStack(spacing: 12) {
            Label {
                Text(InterfaceCopy.servings(servings)).monospacedDigit().contentTransition(.numericText(value: Double(servings)))
            } icon: { Image(systemName: "person.2") }
            if isScaled {
                Button("Reset") { scaledServings = nil }
                    .font(.subheadline)
                    .accessibilityLabel("Reset to \(InterfaceCopy.servings(recipeServings))")
                    .transition(.opacity)
            }
            Spacer()
            Stepper("Servings", value: Binding(get: { servings }, set: { scaledServings = $0 }), in: 1...100)
                .labelsHidden()
                .accessibilityValue(InterfaceCopy.servings(servings))
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : .snappy, value: servings)
        .hapticFeedback(.selection, trigger: servings)
    }
}
