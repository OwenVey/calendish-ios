import SwiftUI

struct GroceryPasteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var reviewing = false
    @State private var discardChanges = false
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .focused($textFocused)
                        .accessibilityLabel("Grocery list to paste")
                        .accessibilityValue(text)
                } header: {
                    Text("One item per line")
                } footer: {
                    Text("Paste a list from Messages or Notes. You can edit or remove items before adding them.")
                }
            }
            .navigationTitle("Paste grocery list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if text.isEmpty { dismiss() } else { discardChanges = true }
                    }.toolbarGlyph()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        textFocused = false
                        reviewing = true
                    } label: { OnAccentLabel(title: "Review items") }
                    .disabled(GroceryPaste.items(from: text).isEmpty)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
            .navigationDestination(isPresented: $reviewing) {
                GroceryPasteReviewView(items: GroceryPaste.items(from: text), onAdded: { dismiss() })
            }
            .task { textFocused = true }
            .confirmationDialog("Discard pasted list?", isPresented: $discardChanges, titleVisibility: .visible) {
                Button("Discard list", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            }
        }
        .background { DraftDismissalGuard(isDirty: !text.isEmpty) { discardChanges = true } }
    }
}
