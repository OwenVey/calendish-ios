import SwiftUI

/// The tab bar accessory counting down to the next running timer, with a menu to resume cooking or cancel timers.
struct RunningTimersAccessory: View {
    /// Reopens Cook Mode for the timer's recipe.
    let onResume: (CookTimer) -> Void
    @Environment(CookingTimers.self) private var timerStore
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let timers = timerStore.timers.sorted { $0.end < $1.end }
        if let next = timers.first {
            Menu {
                // One section per recipe, in the order its soonest timer ends.
                ForEach(timers.filter { timer in timers.first { $0.recipeID == timer.recipeID }?.id == timer.id }) { first in
                    let recipeTimers = timers.filter { $0.recipeID == first.recipeID }
                    Section(first.recipeTitle) {
                        Button("Resume cooking", systemImage: "play") { onResume(first) }
                        ForEach(recipeTimers) { timer in
                            Button("Cancel step \(timer.stepIndex + 1) timer", systemImage: "xmark", role: .destructive) { timerStore.cancel(timer) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "timer").foregroundStyle(CalendishStyle.timer)
                    if placement != .inline {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(next.recipeTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(timers.count > 1 ? "Step \(next.stepIndex + 1) · ^[\(timers.count - 1) more timer](inflect: true)" : "Step \(next.stepIndex + 1)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(timerInterval: Date.now...max(next.end, .now), countsDown: true)
                        .font(.body.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(CalendishStyle.timer)
                }
                .padding(.horizontal, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Menus opening upward reverse their order by default; keep Resume above Cancel.
            .menuOrder(.fixed)
            .accessibilityLabel("Running timers")
        }
    }
}
