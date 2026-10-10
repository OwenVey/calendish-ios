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
                        HStack(spacing: 12) {
                            Label {
                                Text(timerInterval: Date.now...max(timer.end, .now), countsDown: true).monospacedDigit()
                            } icon: { Image(systemName: "timer") }
                                .font(.title3.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                            Button("Cancel timer", role: .destructive) { timerStore.cancel(timer) }
                                .modifier(GlassActionStyle())
                        }
                    } else {
                        Button("Start \(CookTimer.format(duration)) timer", systemImage: "timer") {
                            timerStore.start(recipe: recipe, stepIndex: index, duration: duration)
                        }
                        .controlSize(.large).modifier(GlassActionStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isWide ? 24 : 28).padding(.vertical, isWide ? 12 : 24)
        }
    }
}
