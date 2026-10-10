import SwiftUI

/// Adds a note to a day, or edits one, with optional grocery items.
struct MealNoteEditor: View {
    /// A grocery item line with a stable identity while editing.
    private struct Item: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    let note: MealPlanNote
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeekStart.storageKey) private var weekStart = WeekStart.system
    @State private var text = ""
    @State private var date = Date.now
    @State private var items: [Item] = []
    @State private var initialValues: String?
    @State private var discardChanges = false
    @State private var confirmRemoval = false
    @FocusState private var focusedItem: UUID?
    @FocusState private var textFocused: Bool
    private static let suggestions = ["Leftovers", "Eating out", "Takeout", "Everyone cooks separately"]
    private var isNew: Bool { !store.notes.contains { $0.id == note.id } }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var values: String { ([text, "\(date.timeIntervalSince1970)"] + items.map(\.text)).joined(separator: "|") }
    private var isDirty: Bool { initialValues != nil && values != initialValues }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Note", text: $text, prompt: Text("Leftovers or eating out"))
                        .focused($textFocused)
                        .submitLabel(.done)
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                        .environment(\.calendar, weekStart.calendar)
                } footer: {
                    if isNew && trimmedText.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(Self.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { text = suggestion }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                                    .tint(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                Section {
                    ForEach($items) { $item in
                        TextField("Item", text: $item.text, prompt: Text("Baguette"))
                            .focused($focusedItem, equals: item.id)
                            .submitLabel(.next)
                            .onSubmit(addItem)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button("Add item", systemImage: "plus", action: addItem)
                } header: { Text("Groceries") } footer: {
                    Text("Included when you add this day’s meals to your grocery list.")
                }
                if !isNew {
                    Section {
                        Button("Remove note", role: .destructive) { confirmRemoval = true }
                            .frame(maxWidth: .infinity)
                            .confirmationDialog("Remove this note?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                                Button("Remove note", role: .destructive) {
                                    store.removeNote(note)
                                    dismiss()
                                }
                            }
                    }
                }
            }
            .navigationTitle(isNew ? "Add note" : "Edit note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard note changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard changes", role: .destructive) { dismiss() }
                            Button("Keep editing") { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { OnAccentLabel(title: "Save") }
                        .disabled(trimmedText.isEmpty)
                        .modifier(GlassActionStyle(prominent: true))
                }
            }
            .onAppear {
                guard initialValues == nil else { return }
                text = note.text
                date = note.date
                items = note.items.map { Item(text: $0) }
                initialValues = values
                if isNew { textFocused = true }
            }
        }
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
    }

    private func addItem() {
        // Reuse a blank line rather than piling up empty ones.
        if let blank = items.first(where: { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
            focusedItem = blank.id
            return
        }
        let item = Item(text: "")
        items.append(item)
        focusedItem = item.id
    }

    private func save() {
        store.saveNote(MealPlanNote(id: note.id, date: date, text: text, items: items.map(\.text)))
        dismiss()
    }
}
