import SwiftUI

/// The one way recipes come in from outside the app: links, pasted text, photos, scans, files,
/// drops, and shares. Reads the recipe, then hands it to the editor to review and save.
struct RecipeImportView: View {
    typealias Start = RecipeImportPreparation.Start

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openRecipe) private var openRecipe
    @Environment(HouseholdStore.self) private var store
    @Binding var drafts: RecipeImportDrafts
    @State private var preparation: RecipeImportPreparation

    init(start: Start, drafts: Binding<RecipeImportDrafts>) {
        _drafts = drafts
        _preparation = State(initialValue: RecipeImportPreparation(start: start, drafts: drafts.wrappedValue))
    }

    var body: some View {
        @Bindable var workflow = preparation
        Group {
            switch preparation.phase {
            case .link:
                RecipeImportComposeForm(title: "Import from link", draft: $workflow.drafts.link, error: preparation.composeError,
                                        onImport: importDraft, onPaste: paste, onClear: preparation.clearDraft) {
                    TextField("https://example.com/recipe", text: $workflow.drafts.link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Recipe link")
                        .submitLabel(.go)
                        .onSubmit { importDraft(preparation.drafts.link) }
                } header: {
                    Text("Recipe link")
                } footer: {
                    Text("Paste a link to a recipe page, or to an Instagram, TikTok, YouTube, or Facebook post.")
                }
            case .text:
                RecipeImportComposeForm(title: "Import from text", draft: $workflow.drafts.text, error: preparation.composeError,
                                        onImport: importDraft, onPaste: paste, onClear: preparation.clearDraft) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $workflow.drafts.text)
                            .frame(minHeight: typeSize.isAccessibilitySize ? 180 : 240)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Recipe text")
                        if preparation.drafts.text.isEmpty {
                            Text("Paste a recipe").foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                } header: {
                    Text("Recipe text")
                } footer: {
                    Text("Copy a recipe from a website, note, or message, including its ingredients or instructions.")
                }
            case .reading(let message):
                RecipeImportStatus { ProgressView(message) }
            case .failed(let message, let recognizedText):
                RecipeImportStatus {
                    RecipeImportFailure(message: message, recognizedText: recognizedText, onEditText: preparation.editRecognizedText)
                }
            case .duplicate(let recipe):
                RecipeImportStatus {
                    RecipeImportDuplicate(recipe: recipe) {
                        dismiss()
                        openRecipe(recipe)
                    } onImportAgain: { preparation.importAgain() }
                }
            case .done(let imported): RecipeEditorView(imported: imported)
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .task { preparation.start(recipes: store.recipes) }
        .onChange(of: preparation.drafts) { _, updated in drafts = updated }
        .onDisappear {
            preparation.cancel()
            drafts = preparation.drafts
        }
    }

    private var detents: Set<PresentationDetent> {
        switch preparation.phase {
        case .link: [.medium, .large]
        case .text, .done: [.large]
        case .reading, .failed, .duplicate: [.medium]
        }
    }

    private func importDraft(_ draft: String) {
        preparation.importDraft(draft, recipes: store.recipes)
    }

    private func paste(_ items: [RecipeImport]) {
        preparation.paste(items, recipes: store.recipes)
    }
}
