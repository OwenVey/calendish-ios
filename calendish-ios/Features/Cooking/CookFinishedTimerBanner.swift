import SwiftUI

/// Announces finished timers while voice commands are listening, in place of the blocking alert.
struct CookFinishedTimerBanner: View {
    let handsFree: HandsFreeCooking
    /// The recipe being cooked; timers for other recipes name theirs.
    let recipeID: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !handsFree.finishedTimers.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "timer").foregroundStyle(CalendishStyle.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timer finished").font(.headline)
                    ForEach(handsFree.finishedTimers) { timer in
                        Text("\(timer.recipeID == recipeID ? "" : "\(timer.recipeTitle), ")Step \(timer.stepIndex + 1): \(timer.durationText) timer finished.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .tint(Color.primary)
            }
            .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16).padding(.top, 8)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .default) { handsFree.dismissFinishedTimers() }
    }
}
