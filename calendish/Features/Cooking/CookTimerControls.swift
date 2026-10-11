import SwiftUI

/// The running countdown and controls, with a vertical fallback for large text or narrow panels.
struct CookTimerControls: View {
    let timer: CookTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: timer.isPaused ? "pause.fill" : "timer").contentTransition(.symbolEffect(.replace))
                CookTimerCountdown(timer: timer)
                if timer.isPaused { Text("Paused").font(.headline).foregroundStyle(Color.secondary) }
            }
            .font(.largeTitle.weight(.semibold)).foregroundStyle(CalendishStyle.timer)
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                CookTimerButtons(timer: timer).fixedSize()
                CookTimerButtons(timer: timer).labelStyle(.titleOnly).fixedSize()
                CookTimerButtons(timer: timer, vertical: true)
            }
            .controlSize(.large)
        }
    }
}
