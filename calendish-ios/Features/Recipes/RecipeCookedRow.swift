import SwiftUI

/// When the household last cooked a recipe, opening its history, with a button to mark it cooked today.
struct RecipeCookedRow: View {
    let recipeID: UUID
    let stats: RecipeStats?
    let onShowHistory: () -> Void
    @Environment(HouseholdStore.self) private var store
    private var cookedToday: Bool { stats?.history.isMarked(on: .now) == true }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShowHistory) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CookedHistory.lastCookedText(stats?.history))
                            .foregroundStyle(.primary)
                        if let count = stats?.history.days.count, count > 0 {
                            Text(count == 1 ? "1 day marked cooked or planned" : "\(count) days marked cooked or planned").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows cooked history")
            if cookedToday {
                Label("Cooked today", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button("Mark cooked today", systemImage: "checkmark") { store.markCooked(recipeID) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .hapticFeedback(.success, trigger: cookedToday) { _, cooked in cooked }
    }
}
