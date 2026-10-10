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
        let fullDate = day.formatted(date: .complete, time: .omitted)
        HStack(spacing: 0) {
            Text("\(Text(weekday).foregroundStyle(isToday ? CalendishStyle.accent : Color.primary)) \(Text(day.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(.secondary))")
                .font(.headline)
                .accessibilityLabel(isToday ? Text("Today, \(fullDate)") : Text(fullDate))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Menu {
                Button("Add recipe", systemImage: "book.closed", action: add)
                Button("Add note", systemImage: "note.text", action: addNote)
            } label: {
                Label("Add to \(weekday)", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(CalendishMenuStyle())
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
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(CalendishMenuStyle())
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
        .tint(.primary)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(Color(isThisWeek ? .tertiarySystemFill : .quaternarySystemFill), in: .capsule)
    }
}
