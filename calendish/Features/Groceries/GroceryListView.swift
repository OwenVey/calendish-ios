import SwiftUI

struct GroceryListView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.groceryGrouping) private var grouping = GroceryGrouping.none
    @AppStorage(PreferenceKey.showCompletedGroceries) private var showCompleted = false
    @State private var clearCompleted = false
    @State private var clearAll = false
    @State private var newItem = ""
    @State private var search = ""
    @State private var searchPresented = false
    @State private var scope = GroceryScope.all
    @State private var addingItem = false
    @State private var pastingItems = false
    @State private var sharing: ActivitySheet.Items?
    @State private var lastAddedItemID: UUID?
    @State private var editMode = EditMode.inactive
    @FocusState private var newItemFocused: Bool
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !query.isEmpty }
    private var matchingItems: [GroceryItem] {
        guard isSearching else { return store.groceries.items }
        return store.groceries.items.filter { [$0.name, $0.amount, $0.source].contains { $0.localizedStandardContains(query) } }
    }
    private var activeScope: GroceryScope { searchPresented ? scope : .all }
    private func activeItems(in matching: [GroceryItem]) -> [GroceryItem] { activeScope == .completed ? [] : matching.filter { !$0.isComplete } }
    private func completedItems(in matching: [GroceryItem]) -> [GroceryItem] { activeScope == .toBuy ? [] : matching.filter(\.isComplete) }
    /// Offer to add the search text when the list has nothing by that exact name, so searching doubles as a duplicate check.
    /// Offered unless a row, checked or not, already has the typed name. This follows the search results rather
    /// than `GroceryFood`: a food match the results don't list, like typing "onions" with "1 onion" listed, would hide both.
    private var canAddSearch: Bool {
        isSearching && activeScope != .completed && !store.groceries.items.contains { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }
    }
    /// Sections for the chosen grouping. Items not yet sorted into an aisle wait in an untitled section at the top.
    private func groups(of activeItems: [GroceryItem]) -> [(title: String?, items: [GroceryItem])] {
        switch grouping {
        case .none: [(title: String?.none, items: activeItems)]
        case .recipe:
            // An item for several recipes forms its own section, titled with all of them.
            Dictionary(grouping: activeItems) { $0.sources.formatted(.list(type: .and)) }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
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
        store.groceries.reorder(store.groceries.items.map { ids.contains($0.id) ? iterator.next()! : $0 })
    }
    private func order(_ aisle: GroceryAisle?) -> Int { aisle.flatMap { GroceryAisle.allCases.firstIndex(of: $0) } ?? -1 }
    private var subtitle: String {
        switch store.groceries.remainingCount {
        case 0: store.groceries.items.isEmpty ? "List is empty" : "All checked off"
        case 1: "1 item left"
        case let count: "\(count) items left"
        }
    }

    var body: some View {
        // Filtered once per update; the list, its overlay, and its delete actions all read these.
        let matchingItems = matchingItems
        let activeItems = activeItems(in: matchingItems)
        let completedItems = completedItems(in: matchingItems)
        let canAddSearch = canAddSearch
        ScrollViewReader { scroll in
            List {
                if canAddSearch {
                    Section {
                        Button(action: addSearchItem) {
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
                            .onDelete { offsets in store.groceries.remove(offsets.map { activeItems[$0].id }) }
                            .moveDisabled(searchPresented)
                    }
                } else {
                    ForEach(groups(of: activeItems), id: \.title) { group in
                        Section {
                            ForEach(group.items) { item in GroceryRow(item: item, showsSources: grouping != .recipe) }
                                .onMove { move(group.items, from: $0, to: $1) }
                                .onDelete { offsets in store.groceries.remove(offsets.map { group.items[$0].id }) }
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
                                .onDelete { offsets in store.groceries.remove(offsets.map { completedItems[$0].id }) }
                        }
                    } header: {
                        HStack {
                            Text("\(completedItems.count) checked")
                            Spacer()
                            if !searchPresented {
                                Button(showCompleted ? "Hide" : "Show") { withAnimation(reduceMotion ? nil : .default) { showCompleted.toggle() } }
                                    .font(.subheadline).textCase(nil).frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(showCompleted ? "Hide checked items" : "Show checked items")
                            }
                        }
                    }
                }
            }
            .contentMargins(.bottom, 16, for: .scrollContent)
            .onAppear { store.groceries.clearExpired() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if addingItem {
                    GroceryItemComposer(text: $newItem, isFocused: $newItemFocused, onCancel: cancelAddingItem,
                                        onAdd: addAnotherItem, onSubmit: submitNewItem)
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
            .animation(reduceMotion ? nil : .default, value: store.groceries.items.map(\.isComplete))
            .overlay {
                if searchPresented, activeItems.isEmpty, completedItems.isEmpty, !canAddSearch, !store.groceries.items.isEmpty {
                    if isSearching {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ContentUnavailableView(scope == .completed ? "No checked items" : "Nothing left to buy", systemImage: scope == .completed ? "checkmark.circle" : "basket")
                    }
                } else if store.groceries.items.isEmpty, !addingItem {
                    ContentUnavailableView("All set for now", systemImage: "basket", description: Text("Add an item to start your household grocery list."))
                        .allowsHitTesting(false)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Groceries")
            .tabRootStyle()
            .navigationSubtitle(subtitle)
            .searchable(text: $search, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or add an item")
            .onSubmit(of: .search) { if canAddSearch { addSearchItem() } }
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(GroceryScope.allCases) { Text($0.title).tag($0) }
            }
            .toolbar {
                ToolbarItem(id: "grocery-options", placement: .topBarTrailing) {
                    Menu {
                        Button("Share grocery list", systemImage: "square.and.arrow.up", action: shareGroceryList)
                            .disabled(store.groceries.remainingCount == 0)
                        Button("Paste grocery list", systemImage: "doc.on.clipboard") {
                            cancelAddingItem()
                            pastingItems = true
                        }
                        Picker(selection: $grouping) {
                            ForEach(GroceryGrouping.allCases) { Text($0.rawValue).tag($0) }
                        } label: {
                            Label("Group by", systemImage: "square.grid.3x1.below.line.grid.1x2")
                            Text(grouping.rawValue)
                        }.pickerStyle(.menu)
                        Button("Clear checked items", systemImage: "trash", role: .destructive) { clearCompleted = true }
                            .disabled(!store.groceries.items.contains(where: \.isComplete))
                        Button("Clear grocery list", systemImage: "trash.slash", role: .destructive) { clearAll = true }
                            .disabled(store.groceries.items.isEmpty)
                    } label: { Label("List options", systemImage: "ellipsis") }
                    .confirmationDialog("Clear checked items?", isPresented: $clearCompleted, titleVisibility: .visible) {
                        Button("Clear checked items", role: .destructive) { store.groceries.clearCompleted() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Removes checked items for everyone in your household.")
                    }
                }
                ToolbarItem(id: "grocery-edit", placement: .topBarTrailing) {
                    // A glyph rather than EditButton's text, matching the recipe screen's pencil.
                    Button(editMode.isEditing ? "Done" : "Edit list", systemImage: editMode.isEditing ? "checkmark" : "pencil") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }.toolbarGlyph()
                }
                ToolbarItem(id: "grocery-add", placement: .topBarTrailing) {
                    Button("New item", systemImage: "plus", action: beginAddingItem).toolbarGlyph()
                }
            }
            .calendishAlert("Clear the entire grocery list?", isPresented: $clearAll) {
                Button("Clear grocery list", role: .destructive) { store.groceries.clearAll() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes every item, including ones not yet bought, for everyone in your household.")
            }
            .sheet(isPresented: $pastingItems) { GroceryPasteView() }
            .sheet(item: $sharing) { items in
                ActivitySheet(items: items.values)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    /// Share the whole unchecked list, even when search hides some items.
    private func shareGroceryList() {
        let lines = store.groceries.items.filter { !$0.isComplete }.map { item in
            [item.amount, item.name].filter { !$0.isEmpty }.joined(separator: " ")
        }
        guard !lines.isEmpty else { return }
        sharing = ActivitySheet.Items(values: [lines.joined(separator: "\n")])
    }

    private func beginAddingItem() {
        search = ""
        searchPresented = false
        scope = .all
        addingItem = true
        if newItemFocused { return }
        // The composer's task focuses its field once it enters the layout.
    }

    private func addSearchItem() {
        store.groceries.add(name: query)
        search = ""
    }

    private func addAnotherItem() {
        addNewItem()
        newItemFocused = true
    }

    private func submitNewItem() {
        addNewItem()
        addingItem = false
        newItemFocused = false
    }

    private func cancelAddingItem() {
        newItem = ""
        addingItem = false
        newItemFocused = false
    }

    private func addNewItem() {
        let added = store.groceries.add(names: [newItem])
        newItem = ""
        if let item = added.first { lastAddedItemID = item.id }
    }
}
