import SwiftUI
import PhotosUI

/// What's been typed or pasted, kept by the presenter so it survives closing the sheet.
struct RecipeImportDrafts {
    var link = ""
    var text = ""
}

/// The one way recipes come in from outside the app: links, pasted text, photos, scans, files,
/// drops, and shares. Reads the recipe, then hands it to the editor to review and save.
struct RecipeImportView: View {
    enum Start {
        /// Enter or paste a link.
        case link
        /// Paste or type a recipe's text.
        case text
        case content(RecipeImport)
        case photos([PhotosPickerItem])
    }

    private enum Phase {
        case link
        case text
        case reading(String)
        /// Reading failed. Text recognized from images or a PDF can still be fixed up by hand.
        case failed(String, recognizedText: String?)
        case done(ImportedRecipe)
    }

    @Environment(\.dismiss) private var dismiss
    let start: Start
    @Binding var drafts: RecipeImportDrafts
    @State private var phase: Phase
    @State private var composeError: String?
    @State private var task: Task<Void, Never>?

    init(start: Start, drafts: Binding<RecipeImportDrafts>) {
        self.start = start
        _drafts = drafts
        switch start {
        case .link: _phase = State(initialValue: .link)
        case .text: _phase = State(initialValue: .text)
        case .content, .photos: _phase = State(initialValue: .reading("Reading recipe…"))
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .link: linkForm
            case .text: textForm
            case .reading(let message): status { ProgressView(message) }
            case .failed(let message, let recognizedText): status { failure(message, recognizedText: recognizedText) }
            case .done(let imported): RecipeEditorView(imported: imported)
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .task {
            switch start {
            case .link, .text: break
            case .content(let content): read(content)
            case .photos(let items): readPhotos(items)
            }
        }
        .onDisappear { task?.cancel() }
    }

    private var detents: Set<PresentationDetent> {
        switch phase {
        case .link: [.medium, .large]
        case .text, .done: [.large]
        case .reading, .failed: [.medium]
        }
    }

    // MARK: Reading

    private func read(_ content: RecipeImport) {
        composeError = nil
        phase = .reading(progressMessage(for: content))
        task = Task {
            var recognizedText: String?
            do {
                let imported: ImportedRecipe
                switch content {
                case .link(let url):
                    imported = try await RecipeLinkImporter.fetch(url)
                case .text(let text):
                    imported = try await RecipeTextImporter.parse(text)
                case .images(let images):
                    recognizedText = try await RecipeImageImporter.text(in: images)
                    imported = try await RecipeTextImporter.parse(recognizedText ?? "")
                case .pdf(let data):
                    recognizedText = try await RecipePDFImporter.text(in: data)
                    imported = try await RecipeTextImporter.parse(recognizedText ?? "")
                }
                try Task.checkCancellation()
                phase = .done(imported)
            } catch {
                guard !Task.isCancelled else { return }
                switch content {
                case .link(let url):
                    drafts.link = url.absoluteString
                    composeError = error.localizedDescription
                    phase = .link
                case .text(let text):
                    drafts.text = text
                    composeError = error.localizedDescription
                    phase = .text
                case .images, .pdf:
                    phase = .failed(error.localizedDescription, recognizedText: recognizedText)
                }
            }
        }
    }

    private func readPhotos(_ items: [PhotosPickerItem]) {
        phase = .reading(items.count == 1 ? "Loading photo…" : "Loading \(items.count) photos…")
        task = Task {
            var images: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
            }
            guard !Task.isCancelled else { return }
            if images.isEmpty {
                phase = .failed("Couldn’t load these photos.", recognizedText: nil)
            } else {
                read(.images(images))
            }
        }
    }

    private func progressMessage(for content: RecipeImport) -> String {
        switch content {
        case .link: "Reading recipe page…"
        case .text: "Reading recipe…"
        case .images(let images): images.count == 1 ? "Reading image…" : "Reading \(images.count) images…"
        case .pdf: "Reading PDF…"
        }
    }

    // MARK: Link and text

    private var linkForm: some View {
        composeForm(title: "Add from link", draft: $drafts.link) {
            TextField("https://example.com/recipe", text: $drafts.link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Recipe link")
                .submitLabel(.go)
                .onSubmit { importDraft(drafts.link) }
        } header: {
            Text("Recipe Link")
        } footer: {
            Text("Paste a link to a recipe page.")
        }
    }

    private var textForm: some View {
        composeForm(title: "Add from text", draft: $drafts.text) {
            TextEditor(text: $drafts.text)
                .frame(minHeight: 240)
                .accessibilityLabel("Recipe text")
                .overlay(alignment: .topLeading) {
                    if drafts.text.isEmpty {
                        Text("Paste a recipe")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("Recipe Text")
        } footer: {
            Text("Copy a recipe from a website, note, or message, including its ingredients and instructions.")
        }
    }

    /// Either form takes either kind of input: a link pasted as text is still imported as a link.
    private func importDraft(_ draft: String) {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        read(.from(text: draft))
    }

    private func composeForm(title: String, draft: Binding<String>, @ViewBuilder field: () -> some View,
                             @ViewBuilder header: () -> some View, @ViewBuilder footer: () -> some View) -> some View {
        NavigationStack {
            Form {
                Section {
                    field()
                } header: {
                    HStack {
                        header()
                        Spacer()
                        // Accepts a link, text, an image, or a PDF, without the paste permission prompt.
                        PasteButton(payloadType: RecipeImport.self) { items in
                            Task { @MainActor in paste(items) }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                } footer: {
                    footer()
                }
                Section {
                    Button { importDraft(draft.wrappedValue) } label: {
                        Text("Import")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .modifier(GlassActionStyle(prominent: true))
                    .controlSize(.large)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if let composeError {
                    Section {
                        Text(composeError).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 12, for: .scrollContent)
            .listSectionSpacing(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.toolbarGlyph()
                }
                if !draft.wrappedValue.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", systemImage: "xmark.circle") { draft.wrappedValue = ""; composeError = nil }.toolbarGlyph()
                    }
                }
            }
        }
    }

    /// A pasted link or text goes in the matching form to check before importing; images and PDFs are read right away.
    private func paste(_ items: [RecipeImport]) {
        guard let item = RecipeImport.combined(items) else { return }
        composeError = nil
        switch item {
        case .link(let url):
            drafts.link = url.absoluteString
            phase = .link
        case .text(let text):
            drafts.text = text
            phase = .text
        case .images, .pdf:
            read(item)
        }
    }

    // MARK: Status

    private func status(@ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Import recipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }.toolbarGlyph()
                    }
                }
        }
    }

    private func failure(_ message: String, recognizedText: String?) -> some View {
        ContentUnavailableView {
            Label("Couldn’t Read Recipe", systemImage: "text.viewfinder")
        } description: {
            Text(message)
        } actions: {
            if let recognizedText {
                Button("Edit Text") {
                    drafts.text = recognizedText
                    composeError = nil
                    phase = .text
                }
                .modifier(GlassActionStyle(prominent: true))
            }
        }
    }
}
