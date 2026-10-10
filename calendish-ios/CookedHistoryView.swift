import SwiftUI

/// Every day the household cooked a recipe. Days marked by hand can be removed; past planned meals
/// count too and leave the history when they leave the meal plan.
struct CookedHistoryView: View {
    let recipeID: UUID
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @State private var day = Date.now
    private var history: CookedHistory { store.recipeStats[recipeID]?.history ?? CookedHistory() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
                        .environment(\.calendar, weekStart.calendar)
                    Button("Mark cooked", systemImage: "checkmark") { store.markCooked(recipeID, on: day) }
                        .disabled(history.isMarked(on: day))
                }
                Section {
                    ForEach(history.days, id: \.date) { cooked in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cooked.date.formatted(date: .complete, time: .omitted))
                            Text(cooked.isMarked ? "Marked as cooked" : "Planned meal")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .deleteDisabled(!cooked.isMarked)
                    }
                    .onDelete { offsets in
                        let days = history.days
                        for index in offsets { store.removeCooked(recipeID, on: days[index].date) }
                    }
                    if history.days.isEmpty {
                        Text("No cooking recorded").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("Includes days marked cooked and past planned meals. A past plan doesn’t confirm the meal was cooked. To remove a planned entry, remove it from the meal plan.")
                }
            }
            .navigationTitle("Cooked history").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.toolbarGlyph()
                }
            }
        }
    }
}
