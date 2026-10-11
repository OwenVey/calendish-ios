import SwiftUI

/// One step of cook mode's pager: the instruction, any warnings, and its timer.
struct CookStepPage: View {
    let step: String
    let index: Int
    let recipe: Recipe
    let scale: Double
    /// Running timers for this recipe.
    let timers: [CookTimer]
    let isWide: Bool
    let onIngredientTap: ([UUID]) -> Void
    @Environment(CookingTimers.self) private var timerStore
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    private let session = CookingSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("STEP \(index + 1)").font(.subheadline.weight(.semibold)).tracking(1.4).foregroundStyle(CalendishStyle.accent)
                RecipeStepText(step: step, recipe: recipe, scale: scale, units: units, onIngredientTap: onIngredientTap).font(.title).lineSpacing(6)
                if let warning = session.activityWarning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if let warning = timerStore.notificationWarning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if let duration = CookTimer.duration(in: step) {
                    if let timer = timers.first(where: { $0.stepIndex == index }) {
                        timerControls(timer)
                    } else {
                        Button {
                            timerStore.start(recipe: recipe, stepIndex: index, duration: duration)
                        } label: {
                            Label("Start \(CookTimer.format(duration)) timer", systemImage: "timer").foregroundStyle(.black)
                        }
                        .controlSize(.large).buttonStyle(.glassProminent).tint(CalendishStyle.timer)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isWide ? 24 : 28).padding(.vertical, isWide ? 12 : 24)
        }
    }

    /// The running timer's countdown, with pause, an extra minute, and cancel underneath.
    private func timerControls(_ timer: CookTimer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: timer.isPaused ? "pause.fill" : "timer").contentTransition(.symbolEffect(.replace))
                CookTimerCountdown(timer: timer)
                if timer.isPaused { Text("Paused").font(.headline).foregroundStyle(Color.secondary) }
            }
            .font(.largeTitle.weight(.semibold)).foregroundStyle(CalendishStyle.timer)
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                timerButtons(timer)
                timerButtons(timer).labelStyle(.titleOnly)
            }
            .controlSize(.large)
        }
    }

    private func timerButtons(_ timer: CookTimer) -> some View {
        HStack(spacing: 10) {
            Button {
                if timer.isPaused { timerStore.resume(timer) } else { timerStore.pause(timer) }
            } label: {
                Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill").foregroundStyle(.black)
            }
            .buttonStyle(.glassProminent).tint(CalendishStyle.timer)
            Button("+1 min") { timerStore.addMinute(to: timer) }
                .buttonStyle(.glass).foregroundStyle(.primary)
                .accessibilityLabel("Add 1 minute")
            Button(role: .destructive) { timerStore.cancel(timer) } label: { Label("Cancel", systemImage: "xmark") }
                .buttonStyle(.glass).foregroundStyle(.primary)
                .accessibilityLabel("Cancel timer")
        }
        .fixedSize()
    }
}
