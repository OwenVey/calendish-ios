import SwiftUI

enum GroceryGrouping: String, CaseIterable, Identifiable {
    case none = "None", recipe = "Recipe"
    var id: Self { self }
}

struct GroceryListView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var grouping = GroceryGrouping.none
    @State private var showCompleted = false
    @State private var clearCompleted = false
    @State private var newItem = ""
    @FocusState private var newItemFocused: Bool
    private var activeItems: [GroceryItem] { store.groceries.filter { !$0.isComplete } }
    private var completedItems: [GroceryItem] { store.groceries.filter(\.isComplete) }
    private var groups: [String] { Array(Set(activeItems.map(\.source))).sorted() }
    private var subtitle: String {
        switch store.remainingGroceries {
        case 0: "All done"
        case 1: "1 item left"
        case let count: "\(count) items left"
        }
    }

    var body: some View {
        List {
            if grouping == .none {
                Section {
                    ForEach(activeItems) { item in GroceryRow(item: item) }
                        .onMove { source, destination in
                            // Map the active order back into the full list without moving completed items.
                            var reordered = activeItems
                            reordered.move(fromOffsets: source, toOffset: destination)
                            var iterator = reordered.makeIterator()
                            store.reorderGroceries(store.groceries.map { $0.isComplete ? $0 : iterator.next()! })
                        }
                        .onDelete { offsets in store.removeGroceries(offsets.map { activeItems[$0] }) }
                    newItemRow
                }
            } else {
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        let items = activeItems.filter { $0.source == group }
                        ForEach(items) { item in GroceryRow(item: item) }
                            .onDelete { offsets in store.removeGroceries(offsets.map { items[$0] }) }
                    }
                }
                Section { newItemRow }
            }
            if !completedItems.isEmpty {
                Section {
                    if showCompleted {
                        ForEach(completedItems) { item in GroceryRow(item: item) }
                            .onDelete { offsets in store.removeGroceries(offsets.map { completedItems[$0] }) }
                    }
                } header: {
                    HStack {
                        Text("\(completedItems.count) Completed")
                        Spacer()
                        Button(showCompleted ? "Hide" : "Show") { withAnimation { showCompleted.toggle() } }
                            .font(.subheadline).textCase(nil)
                    }
                }
            }
        }
        .animation(.default, value: store.groceries.map(\.isComplete))
        .overlay {
            if store.groceries.isEmpty && !newItemFocused {
                ContentUnavailableView("All set for now", systemImage: "basket", description: Text("Tap New Item to start your household list."))
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Groceries")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $grouping) {
                        ForEach(GroceryGrouping.allCases) { Text($0.rawValue).tag($0) }
                    } label: {
                        Label("Group By", systemImage: "square.grid.3x1.below.line.grid.1x2")
                        Text(grouping.rawValue)
                    }.pickerStyle(.menu)
                    Button("Clear Completed", systemImage: "trash", role: .destructive) { clearCompleted = true }
                        .disabled(completedItems.isEmpty)
                } label: { Label("List options", systemImage: "ellipsis") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Item", systemImage: "plus") { newItemFocused = true }
            }
        }
        .confirmationDialog("Clear all completed items?", isPresented: $clearCompleted, titleVisibility: .visible) {
            Button("Clear Completed", role: .destructive) { store.clearCompletedGroceries() }
        }
    }

    /// Inline entry like Reminders: Return adds the item and starts the next one.
    private var newItemRow: some View {
        HStack(spacing: 16) {
            Image(systemName: newItemFocused ? "circle" : "plus.circle.fill").font(.title2)
                .foregroundStyle(newItemFocused ? AnyShapeStyle(.tertiary) : AnyShapeStyle(CalendishStyle.accent))
            TextField("New Item", text: $newItem)
                .focused($newItemFocused)
                .submitLabel(.next)
                .onSubmit {
                    addNewItem()
                    newItemFocused = true
                }
        }
        .padding(.vertical, 8)
        .onChange(of: newItemFocused) { _, focused in
            if !focused { addNewItem() }
        }
    }

    private func addNewItem() {
        let name = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        newItem = ""
        guard !name.isEmpty else { return }
        store.addGrocery(name: name)
    }
}

struct GroceryRow: View {
    let item: GroceryItem
    @Environment(HouseholdStore.self) private var store
    @State private var feedback = false
    var body: some View {
        Button {
            store.toggleGrocery(item)
            feedback.toggle()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(item.isComplete ? CalendishStyle.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.body.weight(.medium)).strikethrough(item.isComplete)
                        .foregroundStyle(item.isComplete ? .secondary : .primary)
                    if !item.amount.isEmpty { Text(item.amount).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(item.amount.isEmpty ? item.name : "\(item.name), \(item.amount)")
            .accessibilityValue(item.isComplete ? "Completed" : "Not completed")
            .sensoryFeedback(.selection, trigger: feedback)
    }
}
