import SwiftUI

enum GroceryGrouping: String, CaseIterable, Identifiable {
    case none = "None", recipe = "Recipe", aisle = "Aisle"
    var id: Self { self }
}

enum GroceryScope: String, CaseIterable, Identifiable {
    case all = "All", toBuy = "To Buy", completed = "Completed"
    var id: Self { self }
}

struct GroceryListView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.groceryGrouping) private var grouping = GroceryGrouping.none
    @State private var showCompleted = false
    @State private var clearCompleted = false
    @State private var clearAll = false
    @State private var newItem = ""
    @State private var search = ""
    @State private var searchPresented = false
    @State private var scope = GroceryScope.all
    @State private var addingItem = false
    @State private var lastAddedItemID: UUID?
    @FocusState private var newItemFocused: Bool
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }
    private var matchingItems: [GroceryItem] {
        guard isSearching else { return store.groceries }
        return store.groceries.filter { [$0.name, $0.amount, $0.source].contains { $0.localizedCaseInsensitiveContains(query) } }
    }
    private var activeScope: GroceryScope { searchPresented ? scope : .all }
    private var activeItems: [GroceryItem] { activeScope == .completed ? [] : matchingItems.filter { !$0.isComplete } }
    private var completedItems: [GroceryItem] { activeScope == .toBuy ? [] : matchingItems.filter(\.isComplete) }
    /// Offer to add the search text when the list has nothing by that exact name, so searching doubles as a duplicate check.
    private var canAddSearch: Bool {
        isSearching && activeScope != .completed && !store.groceries.contains { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }
    }
    /// Sections for the chosen grouping. Items not yet sorted into an aisle wait in an untitled section at the top.
    private var groups: [(title: String?, items: [GroceryItem])] {
        switch grouping {
        case .none: [(title: String?.none, items: activeItems)]
        case .recipe:
            Dictionary(grouping: activeItems, by: \.source).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        case .aisle:
            Dictionary(grouping: activeItems) { $0.aisle.map { GroceryAisle(rawValue: $0) ?? .other } }
                .sorted { order($0.key) < order($1.key) }
                .map { ($0.key?.title, $0.value) }
        }
    }
    /// Reorders some of the items, such as one section's, while every other item keeps its place in the full list.
    private func move(_ items: [GroceryItem], from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        var iterator = reordered.makeIterator()
        let ids = Set(items.map(\.id))
        store.reorderGroceries(store.groceries.map { ids.contains($0.id) ? iterator.next()! : $0 })
    }
    private func order(_ aisle: GroceryAisle?) -> Int { aisle.flatMap { GroceryAisle.allCases.firstIndex(of: $0) } ?? -1 }
    private var subtitle: String {
        switch store.remainingGroceries {
        case 0: "All done"
        case 1: "1 item left"
        case let count: "\(count) items left"
        }
    }

    var body: some View {
        ScrollViewReader { scroll in
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
                            .onMove { move(activeItems, from: $0, to: $1) }
                            .onDelete { offsets in store.removeGroceries(offsets.map { activeItems[$0] }) }
                            .moveDisabled(searchPresented)
                    }
                } else {
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.items) { item in GroceryRow(item: item) }
                                .onMove { move(group.items, from: $0, to: $1) }
                                .onDelete { offsets in store.removeGroceries(offsets.map { group.items[$0] }) }
                                .moveDisabled(searchPresented)
                        } header: {
                            if let title = group.title { Text(title) }
                        }
                    }
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
            .contentMargins(.bottom, 16, for: .scrollContent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if addingItem {
                    newItemComposer
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
            }
            .onChange(of: lastAddedItemID) { _, id in
                if let id {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        scroll.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: newItemFocused) { _, focused in
                if !focused { addingItem = false }
            }
            .animation(reduceMotion ? nil : .default, value: store.groceries.map(\.isComplete))
            .overlay {
                if searchPresented && activeItems.isEmpty && completedItems.isEmpty && !canAddSearch && !store.groceries.isEmpty {
                    if isSearching {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ContentUnavailableView(scope == .completed ? "No Completed Items" : "Nothing Left to Buy", systemImage: scope == .completed ? "checkmark.circle" : "basket")
                    }
                } else if store.groceries.isEmpty && !addingItem {
                    ContentUnavailableView("All set for now", systemImage: "basket", description: Text("Tap + to start your household list."))
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Groceries")
            .tabRootStyle()
            .navigationSubtitle(subtitle)
            .searchable(text: $search, isPresented: $searchPresented, prompt: "Search or add an item")
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(GroceryScope.allCases) { Text($0.rawValue).tag($0) }
            }
            .toolbar {
                ToolbarItem(id: "grocery-edit", placement: .topBarLeading) { EditButton().toolbarGlyph() }
                ToolbarItem(id: "grocery-options", placement: .topBarTrailing) {
                    Menu {
                        Picker(selection: $grouping) {
                            ForEach(GroceryGrouping.allCases) { Text($0.rawValue).tag($0) }
                        } label: {
                            Label("Group By", systemImage: "square.grid.3x1.below.line.grid.1x2")
                            Text(grouping.rawValue)
                        }.pickerStyle(.menu)
                        Button("Clear Completed", systemImage: "trash", role: .destructive) { clearCompleted = true }
                            .disabled(!store.groceries.contains(where: \.isComplete))
                        Button("Clear All", systemImage: "trash.slash", role: .destructive) { clearAll = true }
                            .disabled(store.groceries.isEmpty)
                    } label: { Label("List options", systemImage: "ellipsis") }
                }
                ToolbarItem(id: "grocery-add", placement: .topBarTrailing) {
                    Button("New Item", systemImage: "plus", action: beginAddingItem).toolbarGlyph()
                }
            }
            .confirmationDialog("Clear all completed items?", isPresented: $clearCompleted, titleVisibility: .visible) {
                Button("Clear Completed", role: .destructive) { store.clearCompletedGroceries() }
            }
            .confirmationDialog("Clear the entire grocery list?", isPresented: $clearAll, titleVisibility: .visible) {
                Button("Clear All Items", role: .destructive) { store.clearAllGroceries() }
            } message: {
                Text("This removes every item, including ones not yet bought, for everyone in your household.")
            }
        }
    }

    private var newItemComposer: some View {
        HStack(spacing: 12) {
            Button("Cancel New Item", systemImage: "xmark", action: cancelAddingItem)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())

            TextField("e.g. 3 tbsp olive oil", text: $newItem)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($newItemFocused)
                .submitLabel(.done)
                .onSubmit {
                    addNewItem()
                    addingItem = false
                    newItemFocused = false
                }
                .accessibilityLabel("New Grocery Item")

            Button {
                addNewItem()
                newItemFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canAddItem ? CalendishStyle.onAccent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(canAddItem ? .regular.tint(CalendishStyle.accent).interactive() : .regular, in: .circle)
            .disabled(!canAddItem)
            .accessibilityLabel("Add Item")
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            newItemFocused = true
        }
    }

    private var canAddItem: Bool {
        !newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginAddingItem() {
        search = ""
        searchPresented = false
        scope = .all
        addingItem = true
        if newItemFocused { return }
        // The composer's task focuses its field once it enters the layout.
    }

    private func cancelAddingItem() {
        newItem = ""
        addingItem = false
        newItemFocused = false
    }

    private func addNewItem() {
        let name = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        newItem = ""
        guard !name.isEmpty else { return }
        store.addGrocery(name: name)
        lastAddedItemID = store.groceries.last?.id
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
    @State private var pendingCompletion = false
    @State private var editing = false
    @State private var line: String
    @State private var originalLine = ""
    @FocusState private var textFocused: Bool

    init(item: GroceryItem) {
        self.item = item
        _line = State(initialValue: Self.line(for: item))
    }

    private static func line(for item: GroceryItem) -> String {
        [item.amount, item.name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var isChecked: Bool { item.isComplete || pendingCompletion }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                finishEditing()
                if pendingCompletion {
                    pendingCompletion = false
                } else if item.isComplete {
                    store.toggleGrocery(item)
                } else {
                    pendingCompletion = true
                }
                feedback.toggle()
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? CalendishStyle.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isChecked ? "Mark \(item.name) as not completed" : "Complete \(item.name)")
            .accessibilityValue(isChecked ? "Completed" : "Not completed")

            TextField("Grocery Item", text: $line, axis: .vertical)
                .font(.body.weight(.medium))
                .textFieldStyle(.plain)
                .focused($textFocused)
                .submitLabel(.done)
                .foregroundStyle(textFocused ? Color.primary : Color.clear)
                .overlay(alignment: .leading) {
                    if !textFocused {
                        IngredientLineText(line: line)
                            .font(.body.weight(.medium))
                            .strikethrough(isChecked)
                            .foregroundStyle(isChecked ? .secondary : .primary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { textFocused = true }
                .onSubmit { finishEditing() }
                .onChange(of: line) { _, updatedLine in
                    // A vertical TextField inserts a newline from the software
                    // keyboard's Done key instead of invoking onSubmit.
                    if textFocused && updatedLine.contains("\n") {
                        line = updatedLine.replacingOccurrences(of: "\n", with: "")
                        finishEditing()
                    }
                }
                .accessibilityLabel("Grocery Item")
                .accessibilityHint("Edit the grocery item directly")
        }
        .frame(minHeight: 44)
        // The circle's tap target includes 8 points on either side of its glyph.
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 20))
        .sensoryFeedback(.selection, trigger: feedback)
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "trash", role: .destructive) { store.removeGroceries([item]) }
                .tint(.red)
        }
        .accessibilityAction(named: "Edit Item") { textFocused = true }
        .accessibilityAction(named: "Move Up") { move(-1) }
        .accessibilityAction(named: "Move Down") { move(1) }
        .onChange(of: textFocused) { _, focused in
            if focused {
                originalLine = line
                editing = true
            } else {
                finishEditing()
            }
        }
        .onChange(of: Self.line(for: item)) { _, updatedLine in
            if !editing { line = updatedLine }
        }
        .task(id: pendingCompletion) {
            guard pendingCompletion else { return }
            // Let the filled checkmark register before moving into Completed.
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled else { return }
            commitCompletion()
        }
        .onChange(of: item.isComplete) { _, completed in
            if completed { pendingCompletion = false }
        }
        .onDisappear {
            finishEditing()
            // Leaving the tab or scrolling away must still save the checkoff.
            commitCompletion()
        }
    }

    private func commitCompletion() {
        guard pendingCompletion,
              let current = store.groceries.first(where: { $0.id == item.id }),
              !current.isComplete else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            store.toggleGrocery(current)
        }
    }

    private func finishEditing() {
        guard editing else { return }
        editing = false
        textFocused = false
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = store.groceries.first(where: { $0.id == item.id }) else { return }
        guard !trimmed.isEmpty, trimmed != originalLine else {
            line = Self.line(for: current)
            return
        }
        var updated = current
        updated.name = trimmed
        // Keep the whole edited line together, including any quantity.
        updated.amount = ""
        line = trimmed
        store.updateGrocery(updated, original: current)
    }

    private func move(_ direction: Int) {
        var items = store.groceries
        guard let index = items.firstIndex(where: { $0.id == item.id }), items.indices.contains(index + direction) else { return }
        items.swapAt(index, index + direction)
        store.reorderGroceries(items)
    }
}
