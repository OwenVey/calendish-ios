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
                RecipeStepText(step: step, recipe: recipe, scale: scale, units: units, onIngredientTap: onIngredientTap).font(.title).lineSpacing(6)
                if let warning = session.activityWarning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if let warning = timerStore.notificationWarning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if let duration = CookTimer.duration(in: step) {
                    if let timer = timers.first(where: { $0.stepIndex == index }) {
                        CookTimerControls(timer: timer)
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

}
