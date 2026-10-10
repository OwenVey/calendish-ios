import SwiftUI

/// Scales a recipe's ingredients in the grocery review, with a way back to the recipe's own servings.
struct GroceryImportServingsStepper: View {
    let candidate: GroceryImportReview.Section
    @Binding var review: GroceryImportReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let original = candidate.originalServings
        HStack(spacing: 12) {
            Label {
                Text(InterfaceCopy.servings(candidate.servings)).monospacedDigit().contentTransition(.numericText(value: Double(candidate.servings)))
            } icon: { Image(systemName: "person.2") }
            if candidate.servings != original {
                Button("Reset") { review.resetServings(for: candidate.id) }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset to \(InterfaceCopy.servings(original))")
                    .transition(.opacity)
            }
            Spacer()
            Stepper("Servings", value: Binding(get: { candidate.servings }, set: { review.setServings($0, for: candidate.id) }), in: 1...100)
                .labelsHidden()
                .accessibilityValue(InterfaceCopy.servings(candidate.servings))
        }
        .animation(reduceMotion ? nil : .snappy, value: candidate.servings)
    }
}
