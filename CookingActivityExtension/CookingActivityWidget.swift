import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

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
