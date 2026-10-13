import SwiftUI

/// A meal plan day's name and date, with menus to add to it and act on everything planned.
struct MealPlanDayHeader: View {
    let day: Date
    let meals: [PlannedMeal]
    let notes: [MealPlanNote]
    let isThisWeek: Bool
    let isToday: Bool
    let add: () -> Void
    let addNote: () -> Void
    let addToGroceries: () -> Void
    let remove: (PlanRemoval) -> Void
    private var weekday: String { day.formatted(.dateTime.weekday(.wide)) }

    var body: some View {
        MealPlanDayCardHeader(day: day, isEmphasized: isThisWeek, isToday: isToday) {
            Menu {
                Button("Add recipe", systemImage: "book.closed", action: add)
                Button("Add note", systemImage: "note.text", action: addNote)
            } label: {
                Label("Add to \(weekday)", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(.button).buttonStyle(.plain).tint(nil)
            Menu {
                Button("Add to groceries", systemImage: "basket", action: addToGroceries)
                    .disabled(meals.isEmpty && !notes.contains { !$0.items.isEmpty })
                if !meals.isEmpty || !notes.isEmpty {
                    Button(notes.isEmpty ? "Remove all meals" : "Clear day", systemImage: "trash", role: .destructive) {
                        remove(PlanRemoval(meals: meals, notes: notes))
                    }
                }
            } label: {
                // A Menu only hit-tests its label, so the 44pt target has to live inside it.
                Label("More for \(weekday)", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(.button).buttonStyle(.plain).tint(nil)
        }
    }
}
