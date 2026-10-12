import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Prepares an imported recipe draft, including acquisition, duplicate choices and recovery.
/// Presentation reads this state; every attempt owns its lifetime through loading and reading.
@MainActor @Observable
final class RecipeImportPreparation {
    enum Start {
        case link
        case text
        case content(RecipeImport)
        case photos([PhotosPickerItem])
        case files([URL])
    }

    enum Phase {
        case link
        case text
        case reading(String)
        case failed(String, recognizedText: String?)
        case duplicate(Recipe)
        case done(ImportedRecipe)
    }

    var drafts: RecipeImportDrafts
    private(set) var phase: Phase
    private(set) var composeError: String?
    @ObservationIgnored private let reader: RecipeImportReader
    @ObservationIgnored private var initialStart: Start?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var attempt = UUID()
    private var duplicateContent: RecipeImport?
    private var linkText: (url: URL, text: String)?

    init(start: Start, drafts: RecipeImportDrafts = RecipeImportDrafts(), reader: RecipeImportReader = .onDevice) {
        self.drafts = drafts
        self.reader = reader
        initialStart = start
        switch start {
        case .link: phase = .link
        case .text: phase = .text
        case .content, .photos, .files: phase = .reading("Reading recipe…")
        }
    }

    /// Called when presentation opens. Reappearing after opening the editor does not re-read the source.
    func start(recipes: [Recipe]) {
        guard let start = initialStart else { return }
        initialStart = nil
        switch start {
        case .link, .text: break
        case .content(let content): read(content, recipes: recipes)
        case .photos, .files: launch(start)
        }
    }

    /// Invalidates late completions even when a source reader does not cooperate with cancellation.
    func cancel() {
        initialStart = nil
        task?.cancel()
        task = nil
        attempt = UUID()
    }

    func importDraft(_ draft: String, recipes: [Recipe]) {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let content = RecipeImport.from(text: draft)
        if case .link = phase, case .text = content {
            composeError = "Enter a web link beginning with https://. To import recipe text, choose Paste recipe text from New recipe."
            return
        }
        if case .link(let url, nil) = content, let linkText, linkText.url == url {
            read(.link(url, text: linkText.text), recipes: recipes)
        } else {
            read(content, recipes: recipes)
        }
    }

    /// Links and text are checked in the matching form; image and PDF content is read immediately.
    func paste(_ items: [RecipeImport], recipes: [Recipe]) {
        guard let content = RecipeImport.combined(items) else { return }
        cancel()
        duplicateContent = nil
        composeError = nil
        switch content {
        case .link(let url, let text):
            drafts.link = url.absoluteString
            linkText = text.map { (url, $0) }
            phase = .link
        case .text(let text):
            drafts.text = text
            phase = .text
        case .images, .pdf: read(content, recipes: recipes)
        }
    }

    func importAgain() {
        guard case .duplicate = phase, let content = duplicateContent else { return }
        duplicateContent = nil
        launch(.content(content))
    }

    func clearDraft() {
        switch phase {
        case .link: drafts.link = ""; linkText = nil
        case .text: drafts.text = ""
        default: return
        }
        composeError = nil
    }

    func editRecognizedText(_ text: String) {
        cancel()
        drafts.text = text
        composeError = nil
        phase = .text
    }

    private func read(_ content: RecipeImport, recipes: [Recipe]) {
        cancel()
        duplicateContent = nil
        composeError = nil
        if case .link(let url, _) = content, let saved = RecipeSourceLink.recipe(from: url, in: recipes) {
            duplicateContent = content
            phase = .duplicate(saved)
        } else {
            launch(.content(content))
        }
    }

    private func launch(_ start: Start) {
        cancel()
        composeError = nil
        let id = attempt
        switch start {
        case .photos(let items): phase = .reading(items.count == 1 ? "Loading photo…" : "Loading \(items.count) photos…")
        case .files(let urls): phase = .reading(urls.count == 1 ? "Opening file…" : "Opening \(urls.count) files…")
        case .content(let content): phase = .reading(progressMessage(for: content))
        case .link, .text: return
        }
        task = Task { [weak self] in
            guard let self else { return }
            var content: RecipeImport?
            var recognizedText: String?
            defer { if attempt == id { task = nil } }
            do {
                let loaded = try await acquire(start)
                guard attempt == id else { return }
                content = loaded
                phase = .reading(progressMessage(for: loaded))
                let imported: ImportedRecipe
                switch loaded {
                case .link(let url, let text): imported = try await reader.link(url, text)
                case .text(let text): imported = try await reader.text(text)
                case .images(let images):
                    recognizedText = try await reader.images(images)
                    try Task.checkCancellation()
                    guard attempt == id else { return }
                    imported = try await reader.text(recognizedText ?? "")
                case .pdf(let data):
                    recognizedText = try await reader.pdf(data)
                    try Task.checkCancellation()
                    guard attempt == id else { return }
                    imported = try await reader.text(recognizedText ?? "")
                }
                try Task.checkCancellation()
                guard attempt == id else { return }
                phase = .done(imported)
            } catch {
                guard !Task.isCancelled, attempt == id else { return }
                recover(error, content: content, recognizedText: recognizedText)
            }
        }
    }

    private func acquire(_ start: Start) async throws -> RecipeImport {
        switch start {
        case .content(let content): return content
        case .photos(let items):
            var images: [Data] = []
            for (index, item) in items.enumerated() {
                do {
                    try Task.checkCancellation()
                    guard let data = try await reader.photo(item) else { throw CocoaError(.fileReadCorruptFile) }
                    try Task.checkCancellation()
                    images.append(data)
                } catch {
                    throw LoadingFailure(message: "Couldn’t load photo \(index + 1) of \(items.count). Choose the photos again to import every page.")
                }
            }
            guard !images.isEmpty else { throw LoadingFailure(message: "Couldn’t load the photos. Choose them again.") }
            return .images(images)
        case .files(let urls):
            do {
                var items: [RecipeImport] = []
                for url in urls {
                    try Task.checkCancellation()
                    let data = try await reader.file(url)
                    try Task.checkCancellation()
                    items.append(UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true ? .pdf(data) : .images([data]))
                }
                guard let content = RecipeImport.combined(items) else { throw CocoaError(.fileReadCorruptFile) }
                return content
            } catch {
                throw LoadingFailure(message: "Couldn’t open the file. Choose the file again, or try another file.")
            }
        case .link, .text: throw CancellationError()
        }
    }

    private func recover(_ error: Error, content: RecipeImport?, recognizedText: String?) {
        let message = importFailure(error)
        switch content {
        case .link(let url, let text):
            drafts.link = url.absoluteString
            linkText = text.map { (url, $0) }
            composeError = message
            phase = .link
        case .text(let text):
            drafts.text = text
            composeError = message
            phase = .text
        case .images, .pdf, nil:
            phase = .failed(message, recognizedText: recognizedText)
        }
    }

    private func importFailure(_ error: Error) -> String {
        switch error {
        case is LoadingFailure, is RecipeLinkImporter.ImportError, is RecipeTextImporter.ImportError,
             is RecipeImageImporter.ImportError, is RecipePDFImporter.ImportError:
            error.localizedDescription
        default:
            InterfaceCopy.failure(error, action: "read the recipe", recovery: "Try another source or paste the recipe text.")
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

    private struct LoadingFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
