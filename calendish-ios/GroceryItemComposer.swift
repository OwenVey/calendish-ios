import SwiftUI

/// The bar above the keyboard for typing new grocery items, one after another.
struct GroceryItemComposer: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onCancel: () -> Void
    /// Adds the typed item and keeps the field open for the next one.
    let onAdd: () -> Void
    /// Adds the typed item and closes the field.
    let onSubmit: () -> Void
    private var canAdd: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel new item", systemImage: "xmark", action: onCancel)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())

            TextField("e.g. 3 tbsp olive oil", text: $text)
                .font(.body)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .accessibilityLabel("New grocery item")

            Button(action: onAdd) {
                Label("Add item", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canAdd ? CalendishStyle.onAccent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(canAdd ? .regular.tint(CalendishStyle.accent).interactive() : .regular, in: .circle)
            .disabled(!canAdd)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .task {
            // Focus once the composer is in the layout.
            await Task.yield()
            guard !Task.isCancelled else { return }
            isFocused.wrappedValue = true
        }
    }
}
