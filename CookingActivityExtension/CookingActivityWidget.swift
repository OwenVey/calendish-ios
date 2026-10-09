import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CookingActivityBundle: WidgetBundle {
    var body: some Widget { CookingActivityWidget() }
}

struct CookingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingActivityAttributes.self) { context in
            CookingActivityCard(context: context)
                .padding(14)
                .environment(\.colorScheme, .dark)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.cookingURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    CookingActivityCard(context: context, showsHeader: false)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                Image(systemName: "fork.knife").foregroundStyle(.orange)
            } compactTrailing: {
                CookingCompactStatus(context: context)
            } minimal: {
                if let end = context.state.timerEnd, !context.state.isFinished {
                    ProgressView(timerInterval: (context.state.timerStart ?? end.addingTimeInterval(-60))...end,
                        countsDown: true) { Image(systemName: "timer") }
                        .progressViewStyle(.circular).tint(.orange)
                } else {
                    Image(systemName: context.state.isFinished ? "checkmark" : "fork.knife").foregroundStyle(.orange)
                }
            }
            .widgetURL(context.attributes.cookingURL)
            .keylineTint(.orange)
        }
    }
}

private struct CookingActivityCard: View {
    let context: ActivityViewContext<CookingActivityAttributes>
    var showsHeader = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 8 : 4) {
            HStack(alignment: .center, spacing: 8) {
                thumbnail
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
                        timer
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

    private var thumbnail: some View {
        Group {
            if let image = CookingActivityPhoto.image(named: context.state.recipeImageName) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: showsHeader ? 24 : 20, height: showsHeader ? 24 : 20)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var isLastStep: Bool { context.state.stepIndex == context.attributes.stepCount - 1 }

    @ViewBuilder private var timer: some View {
        if let end = context.state.timerEnd {
            Label {
                Text(timerInterval: Date.distantPast...end, countsDown: true)
                    .monospacedDigit().frame(maxWidth: 72, alignment: .leading)
            } icon: { Image(systemName: "timer") }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityLabel("Timer for step \((context.state.timerStepIndex ?? context.state.stepIndex) + 1)")
                .accessibilityValue(Text(timerInterval: Date.distantPast...end, countsDown: true))
        } else if let duration = context.state.suggestedDuration {
            Button(intent: CookingTimerIntent(sessionID: context.attributes.sessionID, stepIndex: context.state.stepIndex)) {
                Label(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)), systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(minHeight: 20).padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(.orange)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityLabel("Start timer")
        } else {
            Label("Cooking", systemImage: "fork.knife")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CookingCompactStatus: View {
    let context: ActivityViewContext<CookingActivityAttributes>
    var body: some View {
        if context.state.isFinished {
            Image(systemName: "checkmark").foregroundStyle(.orange)
        } else if let end = context.state.timerEnd {
            Text(timerInterval: Date.distantPast...end, countsDown: true)
                .monospacedDigit().font(.caption.weight(.semibold))
                .frame(width: 48).foregroundStyle(.orange)
        } else {
            Text("\(context.state.stepIndex + 1)/\(context.attributes.stepCount)")
                .monospacedDigit().font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityLabel("Step \(context.state.stepIndex + 1) of \(context.attributes.stepCount)")
        }
    }
}

#Preview("Cooking", as: .content, using: CookingActivityAttributes(sessionID: UUID(), recipeTitle: "Chicken Bacon Swiss Sandwich", stepCount: 5)) {
    CookingActivityWidget()
} contentStates: {
    CookingActivityAttributes.ContentState(stepIndex: 1,
        instruction: "Pound the chicken to ½-inch thickness and sprinkle with steak seasoning. Grill the chicken over medium heat.",
        suggestedDuration: 240)
    CookingActivityAttributes.ContentState(stepIndex: 1,
        instruction: "Grill the chicken over medium heat until cooked through.",
        timerEnd: .now.addingTimeInterval(240), timerStepIndex: 1, suggestedDuration: 240)
}
