import SwiftUI

/// One day in the meal plan: a header with actions, then its recipes and notes.
struct MealPlanDay: View {
    let day: Date
    let meals: [PlannedMeal]
    let notes: [MealPlanNote]
    /// Days in the current week are solid cards; other weeks recede, and their empty days shrink to a single row.
    let isThisWeek: Bool
    let add: () -> Void
    let edit: (PlannedMeal) -> Void
    let addNote: () -> Void
    let editNote: (MealPlanNote) -> Void
    let remove: (PlanRemoval) -> Void
    /// Moves dropped meals and notes here.
    let move: ([UUID]) -> Void
    let addToGroceries: () -> Void
    @State private var isDropTarget = false
    @State private var dropCount = 0
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isEmpty: Bool { meals.isEmpty && notes.isEmpty }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            MealPlanDayHeader(day: day, meals: meals, notes: notes, isThisWeek: isThisWeek, isToday: isToday,
                              add: add, addNote: addNote, addToGroceries: addToGroceries, remove: remove)
            if isEmpty && isThisWeek {
                Button(action: add) {
                    Label("Add a meal", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add recipe")
            } else {
                ForEach(meals) { MealPlanMealEntry(meal: $0, edit: edit, remove: remove) }
                ForEach(notes) { MealPlanNoteEntry(note: $0, edit: editNote, remove: remove) }
            }
        }
        .padding(6)
        .padding(.bottom, isEmpty && !isThisWeek ? 0 : 4)
        .background(isThisWeek ? CalendishStyle.surface : .clear, in: shape)
        .overlay {
            if isDropTarget {
                shape.fill(CalendishStyle.accent.opacity(0.08))
                shape.strokeBorder(CalendishStyle.accent, lineWidth: 2)
            } else if isToday {
                shape.strokeBorder(CalendishStyle.accent.opacity(0.7), lineWidth: 1.5)
            } else if !isThisWeek {
                shape.strokeBorder(Color(.separator), lineWidth: 1)
            }
        }
        .dropDestination(for: PlannedMealDrag.self) { items, _ in
            let ids = items.map(\.entryID).filter { id in !meals.contains { $0.id == id } && !notes.contains { $0.id == id } }
            guard !ids.isEmpty else { return false }
            move(ids)
            dropCount += 1
            return true
        } isTargeted: { isDropTarget = $0 }
        .animation(.snappy(duration: 0.2), value: isDropTarget)
        .hapticFeedback(.success, trigger: dropCount)
    }
}
