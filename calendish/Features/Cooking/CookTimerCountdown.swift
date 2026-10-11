import SwiftUI

/// A timer's time left: ticking while it runs, held still while paused.
struct CookTimerCountdown: View {
    let timer: CookTimer

    var body: some View {
        Group {
            if let remaining = timer.pausedRemaining {
                Text(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: remaining >= 3600 ? .hourMinuteSecond : .minuteSecond)))
            } else {
                Text(timerInterval: Date.now...max(timer.end, .now), countsDown: true)
            }
        }
        .monospacedDigit()
    }
}

/// Pauses a running timer or resumes a paused one, for timer menus.
struct CookTimerPauseButton: View {
    let timer: CookTimer
    /// What's being paused, such as "timer" or "step 2 timer".
    let title: String
    @Environment(CookingTimers.self) private var timerStore

    var body: some View {
        if timer.isPaused {
            Button("Resume \(title)", systemImage: "play.fill") { timerStore.resume(timer) }
        } else {
            Button("Pause \(title)", systemImage: "pause.fill") { timerStore.pause(timer) }
        }
    }
}
