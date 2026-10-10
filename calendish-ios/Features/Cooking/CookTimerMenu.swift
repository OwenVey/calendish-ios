import SwiftUI

/// The toolbar countdown to the next timer, with each running timer's actions.
struct CookTimerMenu: View {
    /// Running timers for this recipe, soonest first.
    let timers: [CookTimer]
    let onGoToStep: (Int) -> Void
    @Environment(CookingTimers.self) private var timerStore

    var body: some View {
        if let next = timers.first {
            Menu {
                ForEach(timers) { timer in
                    Section("Step \(timer.stepIndex + 1) · \(timer.durationText)") {
                        Button("Go to step", systemImage: "arrow.right") { onGoToStep(timer.stepIndex) }
                        Button("Cancel timer", systemImage: "xmark", role: .destructive) { timerStore.cancel(timer) }
                    }
                }
            } label: {
                Label {
                    Text(timerInterval: Date.now...max(next.end, .now), countsDown: true).monospacedDigit()
                } icon: { Image(systemName: "timer") }
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Running timers")
        }
    }
}
