import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Live Activity's running timer, a button to start the step's timer, or a plain cooking label.
struct CookingActivityTimer: View {
    let context: ActivityViewContext<CookingActivityAttributes>

    var body: some View {
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
