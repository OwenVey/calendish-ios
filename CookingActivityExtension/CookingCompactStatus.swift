import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct CookingCompactStatus: View {
    let context: ActivityViewContext<CookingActivityAttributes>
    var body: some View {
        if context.state.isFinished {
            Image(systemName: "checkmark").foregroundStyle(.orange)
        } else if let end = context.state.timerEnd {
            // A live timer text claims all offered width, so size it to the longest value it will show.
            Text(timerPlaceholder(until: end))
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(timerInterval: Date.distantPast...end, countsDown: true)
                        .multilineTextAlignment(.trailing)
                }
                .monospacedDigit().font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        } else {
            Text("\(context.state.stepIndex + 1)/\(context.attributes.stepCount)")
                .monospacedDigit().font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityLabel("Step \(context.state.stepIndex + 1) of \(context.attributes.stepCount)")
        }
    }

    private func timerPlaceholder(until end: Date) -> String {
        let longest = end.timeIntervalSince(context.state.timerStart ?? .now)
        if longest >= 36000 { return "00:00:00" }
        if longest >= 3600 { return "0:00:00" }
        return "00:00"
    }
}
