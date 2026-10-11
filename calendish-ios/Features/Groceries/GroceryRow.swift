import SwiftUI

struct GroceryRow: View {
    let item: GroceryItem
    /// Lists an item's recipes under it when there are several, unless its section header already does.
    var showsSources = true
    @Environment(HouseholdStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedback = false
    @State private var pendingCompletion = false
    @State private var editing = false
    @State private var line: String
    @State private var originalLine = ""
    @FocusState private var textFocused: Bool

    init(item: GroceryItem, showsSources: Bool = true) {
        self.item = item
        self.showsSources = showsSources
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
                    store.groceries.toggle(item.id)
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
            .accessibilityLabel(isChecked ? "Uncheck \(Self.line(for: item))" : "Check off \(Self.line(for: item))")
            .accessibilityValue(isChecked ? "Checked" : "Unchecked")

            VStack(alignment: .leading, spacing: 2) {
                TextField("Grocery item", text: $line, axis: .vertical)
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
                    .onSubmit { finishEditing() }
                    .onChange(of: line) { _, updatedLine in
                        // A vertical TextField inserts a newline from the software
                        // keyboard's Done key instead of invoking onSubmit.
                        if textFocused, updatedLine.contains("\n") {
                            line = updatedLine.replacingOccurrences(of: "\n", with: "")
                            finishEditing()
                        }
                    }
                    .accessibilityLabel("Grocery item")
                    .accessibilityHint("Edit name and quantity")
                if showsSources, item.sources.count > 1 {
                    Text(item.sources.formatted(.list(type: .and)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("For \(item.sources.formatted(.list(type: .and)))")
                }
            }
            .padding(.vertical, showsSources && item.sources.count > 1 ? 6 : 0)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { textFocused = true }
        }
        .frame(minHeight: 44)
        // The circle's tap target includes 8 points on either side of its glyph.
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 20))
        .hapticFeedback(.selection, trigger: feedback)
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "trash", role: .destructive) { store.groceries.remove([item.id]) }
                .tint(.red)
        }
        .accessibilityAction(named: "Edit item") { textFocused = true }
        .accessibilityAction(named: "Move up") { move(-1) }
        .accessibilityAction(named: "Move down") { move(1) }
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
              let current = store.groceries.items.first(where: { $0.id == item.id }),
              !current.isComplete else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            store.groceries.toggle(current.id)
        }
    }

    private func finishEditing() {
        guard editing else { return }
        editing = false
        textFocused = false
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = store.groceries.items.first(where: { $0.id == item.id }) else { return }
        guard !trimmed.isEmpty, trimmed != originalLine else {
            line = Self.line(for: current)
            return
        }
        var updated = current
        updated.name = trimmed
        // Keep the whole edited line together, including any quantity.
        updated.amount = ""
        line = trimmed
        store.groceries.update(updated, original: current)
    }

    private func move(_ direction: Int) {
        var items = store.groceries.items
        guard let index = items.firstIndex(where: { $0.id == item.id }), items.indices.contains(index + direction) else { return }
        items.swapAt(index, index + direction)
        store.groceries.reorder(items)
    }
}
