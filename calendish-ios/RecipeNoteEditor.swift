import SwiftUI

/// Edits the person's own note on a recipe.
struct RecipeNoteEditor: View {
    let recipeID: UUID
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var initialText: String?
    @State private var discardChanges = false
    @FocusState private var focused: Bool
    private var isDirty: Bool { initialText != nil && text != initialText }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Use half the salt", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($focused)
                } footer: {
                    Text("Household members can see notes on recipes they can access.")
                }
                if initialText?.isEmpty == false {
                    Section {
                        Button("Delete note", role: .destructive) {
                            store.saveReview(of: recipeID, rating: store.myReview(of: recipeID)?.rating, note: "")
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Recipe note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { discardChanges = true } else { dismiss() } }.toolbarGlyph()
                        .confirmationDialog("Discard note changes?", isPresented: $discardChanges, titleVisibility: .visible) {
                            Button("Discard changes", role: .destructive) { dismiss() }
                            Button("Keep editing") { }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        store.saveReview(of: recipeID, rating: store.myReview(of: recipeID)?.rating, note: String(text.prefix(2000)))
                        dismiss()
                    } label: { OnAccentLabel(title: "Save") }
                    .disabled(!isDirty)
                    .modifier(GlassActionStyle(prominent: true))
                }
            }
            .onAppear {
                guard initialText == nil else { return }
                text = store.myReview(of: recipeID)?.note ?? ""
                initialText = text
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .background { DraftDismissalGuard(isDirty: isDirty) { discardChanges = true } }
    }
}
