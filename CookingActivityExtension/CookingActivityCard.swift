import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct CookingActivityCard: View {
    let context: ActivityViewContext<CookingActivityAttributes>
    var showsHeader = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 8 : 4) {
            HStack(alignment: .center, spacing: 8) {
                CookingActivityThumbnail(imageName: context.state.recipeImageName, size: showsHeader ? 24 : 20)
                Text(context.attributes.recipeTitle)
                    .font(.headline.weight(.bold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(context.state.isFinished ? "Finished" : "Step \(context.state.stepIndex + 1)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize()
            }
            Text(context.state.instruction)
                .font(.subheadline)
                .lineLimit(typeSize.isAccessibilitySize ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !context.state.isFinished {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        CookingActivityTimer(context: context)
                        Spacer(minLength: 0)
                        Button(intent: CookingStepIntent(sessionID: context.attributes.sessionID, stepIndex: context.state.stepIndex)) {
                            Label(isLastStep ? "Finish cooking" : "Next", systemImage: isLastStep ? "checkmark" : "arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(minHeight: 20)
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(showsHeader ? .primary : .white)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityLabel(isLastStep ? "Finish cooking" : "Next step")
                    }
                }
            }
        }
        .activityBackgroundTint(.black.opacity(reduceTransparency ? 1 : 0.4))
    }

    private var isLastStep: Bool { context.state.stepIndex == context.attributes.stepCount - 1 }
}
