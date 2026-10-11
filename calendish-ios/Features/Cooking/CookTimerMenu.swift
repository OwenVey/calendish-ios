import SwiftUI

/// The toolbar countdown to the next timer, with each running timer's actions.
struct CookTimerMenu: View {
    /// Timers for this recipe, soonest first.
    let timers: [CookTimer]
    let onGoToStep: (Int) -> Void
    @Environment(CookingTimers.self) private var timerStore

    var body: some View {
        if let next = timers.first {
            Menu {
                ForEach(timers) { timer in
                    Section("Step \(timer.stepIndex + 1) · \(timer.durationText)") {
                        Button("Go to step", systemImage: "arrow.right") { onGoToStep(timer.stepIndex) }
                        CookTimerPauseButton(timer: timer, title: "timer")
                        Button("Add 1 minute", systemImage: "plus") { timerStore.addMinute(to: timer) }
                        Button("Cancel timer", systemImage: "xmark", role: .destructive) { timerStore.cancel(timer) }
                    }
                }
            } label: {
                Label {
                    CookTimerCountdown(timer: next)
                } icon: { Image(systemName: "timer") }
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Running timers")
        }
    }
}
