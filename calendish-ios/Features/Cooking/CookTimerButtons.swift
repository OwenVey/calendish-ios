import SwiftUI

struct CookTimerButtons: View {
    let timer: CookTimer
    var vertical = false
    @Environment(CookingTimers.self) private var timerStore

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Button(action: togglePause) {
                Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill")
                    .foregroundStyle(.black)
            }
            .buttonStyle(.glassProminent).tint(CalendishStyle.timer)
            Button("+1 min", action: addMinute)
                .buttonStyle(.glass).foregroundStyle(.primary)
                .accessibilityLabel("Add 1 minute")
            Button(role: .destructive, action: cancel) { Label("Cancel", systemImage: "xmark") }
                .buttonStyle(.glass).foregroundStyle(.primary)
                .accessibilityLabel("Cancel timer")
        }
    }

    private func togglePause() {
        if timer.isPaused { timerStore.resume(timer) } else { timerStore.pause(timer) }
    }
    private func addMinute() { timerStore.addMinute(to: timer) }
    private func cancel() { timerStore.cancel(timer) }
}
