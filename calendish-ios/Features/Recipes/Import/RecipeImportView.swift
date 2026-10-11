import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
        case files([URL])
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
    /// Text shared or pasted along with the link in the link form, such as a post's caption, kept for trying again.
    @State private var linkText: (url: URL, text: String)?

    init(start: Start, drafts: Binding<RecipeImportDrafts>) {
        self.start = start
        _drafts = drafts
        switch start {
        case .link: _phase = State(initialValue: .link)
        case .text: _phase = State(initialValue: .text)
        case .content, .photos, .files: _phase = State(initialValue: .reading("Reading recipe…"))
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .link:
                RecipeImportComposeForm(title: "Import from link", draft: $drafts.link, error: composeError,
                                        onImport: importDraft, onPaste: paste, onClear: { clearDraft($drafts.link) }) {
                    TextField("https://example.com/recipe", text: $drafts.link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Recipe link")
                        .submitLabel(.go)
                        .onSubmit { importDraft(drafts.link) }
                } header: {
                    Text("Recipe link")
                } footer: {
                    Text("Paste a link to a recipe page, or to an Instagram, TikTok, or YouTube post.")
                }
            case .text:
                RecipeImportComposeForm(title: "Import from text", draft: $drafts.text, error: composeError,
                                        onImport: importDraft, onPaste: paste, onClear: { clearDraft($drafts.text) }) {
                    TextField("Recipe text", text: $drafts.text, prompt: Text("Paste a recipe"), axis: .vertical)
                        .lineLimit(10...)
                } header: {
                    Text("Recipe text")
                } footer: {
                    Text("Copy a recipe from a website, note, or message, including its ingredients or instructions.")
                }
            case .reading(let message):
                RecipeImportStatus { ProgressView(message) }
            case .failed(let message, let recognizedText):
                RecipeImportStatus {
                    RecipeImportFailure(message: message, recognizedText: recognizedText, onEditText: editRecognizedText)
                }
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
            case .files(let urls): readFiles(urls)
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

    private func importFailure(_ error: Error) -> String {
        switch error {
        case is RecipeLinkImporter.ImportError, is RecipeTextImporter.ImportError,
             is RecipeImageImporter.ImportError, is RecipePDFImporter.ImportError:
            return error.localizedDescription
        default:
            return InterfaceCopy.failure(error, action: "read the recipe", recovery: "Try another source or paste the recipe text.")
        }
    }

    private func read(_ content: RecipeImport) {
        composeError = nil
        phase = .reading(progressMessage(for: content))
        task = Task {
            var recognizedText: String?
            do {
                let imported: ImportedRecipe
                switch content {
                case .link(let url, let text):
                    imported = try await RecipeLinkImporter.fetch(url, sharedText: text)
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
                case .link(let url, let text):
                    drafts.link = url.absoluteString
                    linkText = text.map { (url, $0) }
                    composeError = importFailure(error)
                    phase = .link
                case .text(let text):
                    drafts.text = text
                    composeError = importFailure(error)
                    phase = .text
                case .images, .pdf:
                    phase = .failed(importFailure(error), recognizedText: recognizedText)
                }
            }
        }
    }

    private func readPhotos(_ items: [PhotosPickerItem]) {
        phase = .reading(items.count == 1 ? "Loading photo…" : "Loading \(items.count) photos…")
        task = Task {
            var images: [Data] = []
            for (index, item) in items.enumerated() {
                do {
                    try Task.checkCancellation()
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    images.append(data)
                } catch {
                    guard !Task.isCancelled else { return }
                    phase = .failed("Couldn’t load photo \(index + 1) of \(items.count). Choose the photos again to import every page.", recognizedText: nil)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            if images.isEmpty {
                phase = .failed("Couldn’t load the photos. Choose them again.", recognizedText: nil)
            } else {
                read(.images(images))
            }
        }
    }

    private func readFiles(_ urls: [URL]) {
        phase = .reading(urls.count == 1 ? "Opening file…" : "Opening \(urls.count) files…")
        task = Task {
            do {
                var items: [RecipeImport] = []
                for url in urls {
                    let data = try await ImportFileReader.shared.read(url)
                    items.append(UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true ? .pdf(data) : .images([data]))
                }
                try Task.checkCancellation()
                guard let content = RecipeImport.combined(items) else { throw CocoaError(.fileReadCorruptFile) }
                read(content)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed("Couldn’t open the file. Choose the file again, or try another file.", recognizedText: nil)
            }
        }
    }

    private func progressMessage(for content: RecipeImport) -> String {
        switch content {
        case .link(let url, _): SocialPost.Platform(url) == nil ? "Reading recipe page…" : "Reading post…"
        case .text: "Reading recipe…"
        case .images(let images): images.count == 1 ? "Reading image…" : "Reading \(images.count) images…"
        case .pdf: "Reading PDF…"
        }
    }

    // MARK: Link and text

    /// Either form takes either kind of input: a link pasted as text is still imported as a link.
    private func importDraft(_ draft: String) {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let content = RecipeImport.from(text: draft)
        if case .link(let url, nil) = content, let linkText, linkText.url == url {
            read(.link(url, text: linkText.text))
        } else {
            read(content)
        }
    }

    /// A pasted link or text goes in the matching form to check before importing; images and PDFs are read right away.
    private func paste(_ items: [RecipeImport]) {
        guard let item = RecipeImport.combined(items) else { return }
        composeError = nil
        switch item {
        case .link(let url, let text):
            drafts.link = url.absoluteString
            linkText = text.map { (url, $0) }
            phase = .link
        case .text(let text):
            drafts.text = text
            phase = .text
        case .images, .pdf:
            read(item)
        }
    }

    private func clearDraft(_ draft: Binding<String>) {
        draft.wrappedValue = ""
        composeError = nil
    }

    private func editRecognizedText(_ text: String) {
        drafts.text = text
        composeError = nil
        phase = .text
    }
}
