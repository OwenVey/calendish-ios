import SwiftUI

enum GroceryGrouping: String, CaseIterable, Identifiable {
    case none = "None", recipe = "Recipe"
    var id: Self { self }
}

enum GroceryScope: String, CaseIterable, Identifiable {
    case all = "All", toBuy = "To Buy", completed = "Completed"
    var id: Self { self }
}

struct GroceryListView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grouping = GroceryGrouping.none
    @State private var showCompleted = false
    @State private var clearCompleted = false
    @State private var newItem = ""
    @State private var search = ""
    @State private var searchPresented = false
    @State private var scope = GroceryScope.all
    @FocusState private var newItemFocused: Bool
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }
    private var matchingItems: [GroceryItem] {
        guard isSearching else { return store.groceries }
        return store.groceries.filter { [$0.name, $0.amount, $0.source].contains { $0.localizedCaseInsensitiveContains(query) } }
    }
    private var activeItems: [GroceryItem] { scope == .completed ? [] : matchingItems.filter { !$0.isComplete } }
    private var completedItems: [GroceryItem] { scope == .toBuy ? [] : matchingItems.filter(\.isComplete) }
    /// Offer to add the search text when the list has nothing by that exact name, so searching doubles as a duplicate check.
    private var canAddSearch: Bool {
        isSearching && scope != .completed && !store.groceries.contains { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }
    }
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
            if canAddSearch {
                Section {
                    Button {
                        store.addGrocery(name: query)
                        search = ""
                    } label: {
                        Label { Text("Add “\(query)”") } icon: {
                            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(CalendishStyle.accent)
                        }
                        .labelStyle(GroceryAddLabelStyle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                }
            }
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
                        .moveDisabled(searchPresented)
                    if !searchPresented { newItemRow }
                }
            } else {
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        let items = activeItems.filter { $0.source == group }
                        ForEach(items) { item in GroceryRow(item: item) }
                            .onDelete { offsets in store.removeGroceries(offsets.map { items[$0] }) }
                    }
                }
                if !searchPresented { Section { newItemRow } }
            }
            if !completedItems.isEmpty {
                Section {
                    // Search results include completed matches so nothing on the list is hidden from a search.
                    if showCompleted || searchPresented {
                        ForEach(completedItems) { item in GroceryRow(item: item) }
                            .onDelete { offsets in store.removeGroceries(offsets.map { completedItems[$0] }) }
                    }
                } header: {
                    HStack {
                        Text("\(completedItems.count) Completed")
                        Spacer()
                        if !searchPresented {
                            Button(showCompleted ? "Hide" : "Show") { withAnimation(reduceMotion ? nil : .default) { showCompleted.toggle() } }
                                .font(.subheadline).textCase(nil).frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: store.groceries.map(\.isComplete))
        .overlay {
            if searchPresented && activeItems.isEmpty && completedItems.isEmpty && !canAddSearch && !store.groceries.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView(scope == .completed ? "No Completed Items" : "Nothing Left to Buy", systemImage: scope == .completed ? "checkmark.circle" : "basket")
                }
            } else if store.groceries.isEmpty && !newItemFocused {
                ContentUnavailableView("All set for now", systemImage: "basket", description: Text("Tap New Item to start your household list."))
                    .allowsHitTesting(false)
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Groceries")
        .tabRootStyle()
        .navigationSubtitle(subtitle)
        .searchable(text: $search, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or add an item")
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(GroceryScope.allCases) { Text($0.rawValue).tag($0) }
        }
        .onChange(of: searchPresented) { _, presented in
            if !presented { scope = .all }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton().disabled(grouping != .none || searchPresented).toolbarGlyph() }
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
                Button("New Item", systemImage: "plus") { newItemFocused = true }.toolbarGlyph()
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

/// Lines the add-from-search row up with grocery rows' checkmark column.
private struct GroceryAddLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.icon
            configuration.title.font(.body.weight(.medium))
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct GroceryRow: View {
    let item: GroceryItem
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedback = false
    @State private var editing = false
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
            .swipeActions(edge: .trailing) {
                // Custom trailing actions replace the list's onDelete swipe, so Delete is restated here.
                Button("Delete", systemImage: "trash", role: .destructive) { store.removeGroceries([item]) }
                Button("Edit", systemImage: "pencil") { editing = true }
            }
            .accessibilityAction(named: "Edit Item") { editing = true }
            .accessibilityAction(named: "Move Up") { move(-1) }
            .accessibilityAction(named: "Move Down") { move(1) }
            .sheet(isPresented: $editing) { GroceryEditorView(item: item) }
    }
    private func move(_ direction: Int) {
        var items = store.groceries
        guard let index = items.firstIndex(where: { $0.id == item.id }), items.indices.contains(index + direction) else { return }
        items.swapAt(index, index + direction)
        store.reorderGroceries(items)
    }
}

private struct GroceryEditorView: View {
    let item: GroceryItem
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: String
    @State private var discard = false
    init(item: GroceryItem) {
        self.item = item
        _name = State(initialValue: item.name)
        _amount = State(initialValue: item.amount)
    }
    private var isDirty: Bool { name != item.name || amount != item.amount }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Item Name (Required)", text: $name)
                TextField("Amount", text: $amount)
            }
            .navigationTitle("Edit Grocery Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if isDirty { discard = true } else { dismiss() } }.toolbarGlyph() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.updateGrocery(updated, original: item); dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).modifier(GlassActionStyle(prominent: true))
                }
            }
        }
        .background { DraftDismissalGuard(isDirty: isDirty) { discard = true } }
        .confirmationDialog("Discard Changes?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing") { }
        }
    }
}
