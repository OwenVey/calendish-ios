import SwiftUI

/// One day in the meal plan: a header with actions, then its recipes and notes.
struct MealPlanDay: View {
    let day: Date
    let meals: [PlannedMeal]
    let notes: [MealPlanNote]
    /// Today and future days are solid cards; past days recede, and their empty days shrink to a single row.
    let isEmphasized: Bool
    let add: () -> Void
    let edit: (PlannedMeal) -> Void
    let addNote: () -> Void
    let editNote: (MealPlanNote) -> Void
    let remove: (PlanRemoval) -> Void
    /// Moves dropped meals and notes here.
    let move: ([UUID]) -> Void
    /// Reviews groceries for the whole day, or for one meal from its menu.
    let addToGroceries: ([PlannedMeal], [MealPlanNote]) -> Void
    @State private var isDropTarget = false
    @State private var dropCount = 0
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isEmpty: Bool { meals.isEmpty && notes.isEmpty }

    var body: some View {
        MealPlanDayCard(day: day, isEmphasized: isEmphasized, isEmpty: isEmpty, isDropTarget: isDropTarget) {
            MealPlanDayHeader(day: day, meals: meals, notes: notes, isEmphasized: isEmphasized, isToday: isToday,
                              add: add, addNote: addNote, addToGroceries: { addToGroceries(meals, notes) }, remove: remove)
        } content: {
            if isEmpty, isEmphasized {
                MealPlanDayEmptyEntry(title: "Add a meal", accessibilityLabel: "Add recipe", action: add)
            } else {
                ForEach(meals) { MealPlanMealEntry(meal: $0, edit: edit, remove: remove) { addToGroceries([$0], []) } }
                ForEach(notes) { MealPlanNoteEntry(note: $0, edit: editNote, remove: remove) }
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
