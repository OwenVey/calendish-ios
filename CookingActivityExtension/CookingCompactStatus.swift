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
