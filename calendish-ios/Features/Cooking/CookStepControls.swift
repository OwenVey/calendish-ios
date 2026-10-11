import SwiftUI

/// Previous and next buttons around a step picker, with Finish in place of Next on the last step.
struct CookStepControls: View {
    @Binding var stepIndex: Int
    let stepCount: Int
    /// Whether finishing records the recipe as cooked.
    let recordsCook: Bool
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isLastStep: Bool { stepIndex >= stepCount - 1 }

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                Button(action: previous) {
                    Label("Previous step", systemImage: "arrow.left")
                        .labelStyle(.iconOnly)
                        .font(.title2.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                    .tint(Color.primary)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .disabled(stepIndex == 0)
                Spacer(minLength: 0)
                Menu {
                    Picker("Step", selection: $stepIndex) {
                        ForEach(0..<stepCount, id: \.self) { index in
                            Text("Step \(index + 1)").tag(index)
                        }
                    }
                } label: {
                    Text("Step \(stepIndex + 1) of \(stepCount)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                        .frame(minHeight: 44)
                }
                .tint(Color.primary)
                .accessibilityHint("Choose a step")
                Spacer(minLength: 0)
                // Finish matches Next's size and shape, so the step count stays put on the last step.
                Button(action: isLastStep ? onFinish : next) {
                    Label(isLastStep ? "Finish cooking" : "Next step", systemImage: isLastStep ? "checkmark" : "arrow.right")
                        .labelStyle(.iconOnly)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(CalendishStyle.onAccent)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .accessibilityHint(isLastStep ? (recordsCook ? "Records this recipe as cooked and closes cook mode" : "Closes cook mode") : "")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func previous() {
        withAnimation(reduceMotion ? nil : .default) { stepIndex = max(0, stepIndex - 1) }
    }

    private func next() {
        withAnimation(reduceMotion ? nil : .default) { stepIndex = min(stepCount - 1, stepIndex + 1) }
    }
}
