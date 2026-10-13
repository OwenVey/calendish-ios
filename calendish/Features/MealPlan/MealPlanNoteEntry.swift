import SwiftUI

/// A note in a meal plan day: opens its editor, drags to another day, and edits or removes from its menu.
struct MealPlanNoteEntry: View {
    let note: MealPlanNote
    let edit: (MealPlanNote) -> Void
    let remove: (PlanRemoval) -> Void

    var body: some View {
        Button { edit(note) } label: {
            MealNoteRow(note: note)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .accessibilityHint("Edits the note")
        .draggable(PlannedMealDrag(entryID: note.id)) {
            MealNoteRow(note: note)
                .padding(10)
                .frame(width: 320, alignment: .leading)
                .background(CalendishStyle.surface, in: .rect(cornerRadius: 20, style: .continuous))
        }
        .calendishContextMenu {
            Button("Edit note", systemImage: "pencil") { edit(note) }
            Button("Remove note", systemImage: "trash", role: .destructive) { remove(PlanRemoval(notes: [note])) }
        }
        .accessibilityAction(named: "Edit note") { edit(note) }
        .accessibilityAction(named: "Remove note") { remove(PlanRemoval(notes: [note])) }
    }
}
