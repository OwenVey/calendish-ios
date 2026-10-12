import PhotosUI
import SwiftUI

@main
struct RecipeImportPreparationTestApp: App {
    @State private var result = "Running import preparation tests…"
    var body: some Scene {
        WindowGroup {
            Text(result).padding().task {
                do { try await run(); result = "PASS" }
                catch { result = "FAIL: \(error)" }
                try? Data(result.utf8).write(to: URL.documentsDirectory.appending(path: "result.txt"))
            }
        }
    }

    @MainActor private final class Gate {
        var entered = false
        var returned = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            await withCheckedContinuation { entered = true; continuation = $0 }
            returned = true
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    private func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now >= deadline { throw NSError(domain: "Timed out waiting for import state", code: 1) }
            await Task.yield()
        }
    }

    private func imported(_ title: String) -> ImportedRecipe {
        var recipe = SampleRecipes.all[0]
        recipe.title = title
        return ImportedRecipe(recipe: recipe)
    }

    private func reader() -> RecipeImportReader {
        RecipeImportReader(
            photo: { _ in Data("photo".utf8) }, file: { _ in Data("file".utf8) },
            link: { _, _ in imported("Read link") }, text: { imported($0) },
            images: { _ in "Recognized images" }, pdf: { _ in "Recognized PDF" }
        )
    }

    private func doneTitle(_ preparation: RecipeImportPreparation) -> String? {
        if case .done(let imported) = preparation.phase { return imported.recipe.title }
        return nil
    }

    private func run() async throws {
        try await duplicateAndRetry()
        try await formValidationAndRecovery()
        try await recognizedTextRecovery()
        try await loadingFailuresAndOrder()
        try await replacedAttemptCannotPublish()
        try await cancelledLoadingCannotRead()
        try await cancellationKeepsDrafts()
    }

    private func duplicateAndRetry() async throws {
        let url = URL(string: "https://example.com/soup?utm_source=share")!
        var saved = SampleRecipes.all[0]
        saved.recipeLink = "https://example.com/soup"
        var calls: [(URL, String?)] = []
        var source = reader()
        source.link = { url, caption in
            calls.append((url, caption))
            if calls.count == 1 { throw RecipeLinkImporter.ImportError.noRecipe }
            return imported("Imported again")
        }
        let preparation = RecipeImportPreparation(start: .link, reader: source)
        preparation.start(recipes: [])
        preparation.paste([.link(url), .text("Shared caption")], recipes: [])
        // The collection is supplied at attempt time, rather than retained when the sheet opened.
        preparation.importDraft(preparation.drafts.link, recipes: [saved])
        guard case .duplicate(let duplicate) = preparation.phase else { throw NSError(domain: "Expected duplicate", code: 1) }
        try expect(duplicate.id == saved.id && calls.isEmpty, "Duplicate choice happens before source reading")
        preparation.importAgain()
        try await until { preparation.composeError != nil }
        try expect(preparation.drafts.link == url.absoluteString, "Failed link returns to its entered draft")
        preparation.importDraft(preparation.drafts.link, recipes: [])
        try await until { doneTitle(preparation) != nil }
        try expect(calls.count == 2 && calls.allSatisfy { $0.1 == "Shared caption" }, "Import-again and retry retain the shared caption")
        try expect(doneTitle(preparation) == "Imported again", "Retry opens the imported draft")
        preparation.start(recipes: [])
        try expect(calls.count == 2, "Presentation reappearance does not repeat preparation")
    }

    private func formValidationAndRecovery() async throws {
        var reads = 0
        var source = reader()
        source.text = { _ in reads += 1; throw RecipeTextImporter.ImportError.unrecognized }
        let preparation = RecipeImportPreparation(start: .link, reader: source)
        preparation.importDraft("not-a-url", recipes: [])
        try expect(preparation.composeError != nil && reads == 0, "Invalid link never reaches the reader")
        preparation.clearDraft()
        try expect(preparation.composeError == nil, "Clear removes the form error")
        preparation.paste([.text("Entered recipe")], recipes: [])
        preparation.importDraft(preparation.drafts.text, recipes: [])
        try await until { preparation.composeError != nil }
        guard case .text = preparation.phase else { throw NSError(domain: "Text failure lost its form", code: 1) }
        try expect(preparation.drafts.text == "Entered recipe", "Failed text remains editable")
    }

    private func recognizedTextRecovery() async throws {
        for content in [RecipeImport.images([Data()]), .pdf(Data())] {
            var source = reader()
            source.text = { _ in throw RecipeTextImporter.ImportError.unrecognized }
            let preparation = RecipeImportPreparation(start: .content(content), reader: source)
            preparation.start(recipes: [])
            try await until { if case .failed = preparation.phase { true } else { false } }
            guard case .failed(_, let text?) = preparation.phase else { throw NSError(domain: "Recognized text was lost", code: 1) }
            preparation.editRecognizedText(text)
            guard case .text = preparation.phase else { throw NSError(domain: "Recovery did not open text form", code: 1) }
            try expect(preparation.drafts.text == text && preparation.composeError == nil, "Recognized text becomes the editable draft")
        }
    }

    private func loadingFailuresAndOrder() async throws {
        var source = reader()
        var photoCalls = 0
        var recognizedImages: [Data] = []
        source.photo = { _ in photoCalls += 1; return Data([UInt8(photoCalls)]) }
        source.images = { images in recognizedImages = images; return "Ordered photos" }
        let photos = [PhotosPickerItem(itemIdentifier: "first"), PhotosPickerItem(itemIdentifier: "second")]
        let preparation = RecipeImportPreparation(start: .photos(photos), reader: source)
        preparation.start(recipes: [])
        try await until { doneTitle(preparation) != nil }
        try expect(recognizedImages == [Data([1]), Data([2])], "Selected photos are read in order")
        source.photo = { _ in photoCalls += 1; return photoCalls == 3 ? Data([1]) : nil }
        let failedPhotos = RecipeImportPreparation(start: .photos(photos), reader: source)
        failedPhotos.start(recipes: [])
        try await until { if case .failed = failedPhotos.phase { true } else { false } }
        guard case .failed(let message, nil) = failedPhotos.phase else { throw NSError(domain: "Expected photo loading failure", code: 1) }
        try expect(message.contains("photo 2 of 2") && recognizedImages.count == 2, "A missing page rejects the entire import before recognition")
        source.file = { _ in throw CocoaError(.fileReadNoSuchFile) }
        let files = RecipeImportPreparation(start: .files([URL(filePath: "/missing.pdf")]), reader: source)
        files.start(recipes: [])
        try await until { if case .failed = files.phase { true } else { false } }
        guard case .failed(let fileMessage, nil) = files.phase else { throw NSError(domain: "Expected file failure", code: 1) }
        try expect(fileMessage.contains("Couldn’t open the file"), "File acquisition preserves recovery guidance")
    }

    private func replacedAttemptCannotPublish() async throws {
        for fails in [false, true] {
            let gate = Gate()
            var source = reader()
            source.text = { text in
                if text == "Older" {
                    await gate.wait() // Deliberately ignores cancellation.
                    if fails { throw RecipeTextImporter.ImportError.unrecognized }
                }
                return imported(text)
            }
            let preparation = RecipeImportPreparation(start: .text, reader: source)
            preparation.importDraft("Older", recipes: [])
            try await until { gate.entered }
            preparation.importDraft("Newer", recipes: [])
            try await until { doneTitle(preparation) == "Newer" }
            gate.release()
            try await until { gate.returned }
            for _ in 0..<5 { await Task.yield() }
            try expect(doneTitle(preparation) == "Newer" && preparation.composeError == nil, "Late success and failure cannot overwrite the newer draft")
        }
    }

    private func cancelledLoadingCannotRead() async throws {
        for photos in [true, false] {
            let gate = Gate()
            var reads = 0
            var source = reader()
            source.photo = { _ in await gate.wait(); return Data() }
            source.file = { _ in await gate.wait(); return Data() }
            source.images = { _ in reads += 1; return "Old images" }
            source.pdf = { _ in reads += 1; return "Old PDF" }
            let start: RecipeImportPreparation.Start = photos ? .photos([PhotosPickerItem(itemIdentifier: "delayed")]) : .files([URL(filePath: "/delayed.pdf")])
            let preparation = RecipeImportPreparation(start: start, reader: source)
            preparation.start(recipes: [])
            try await until { gate.entered }
            preparation.paste([.text("New draft")], recipes: [])
            gate.release()
            try await until { gate.returned }
            for _ in 0..<5 { await Task.yield() }
            try expect(reads == 0 && preparation.drafts.text == "New draft", "Cancelled loading cannot start reading or overwrite pasted text")
            guard case .text = preparation.phase else { throw NSError(domain: "Late loading changed presentation", code: 1) }
        }
    }

    private func cancellationKeepsDrafts() async throws {
        var unopenedReads = 0
        var unopenedReader = reader()
        unopenedReader.text = { text in unopenedReads += 1; return imported(text) }
        let unopened = RecipeImportPreparation(start: .content(.text("Not opened")), reader: unopenedReader)
        unopened.cancel()
        unopened.start(recipes: [])
        await Task.yield()
        try expect(unopenedReads == 0, "Dismissal before presentation starts prevents preparation")
        let gate = Gate()
        var source = reader()
        source.text = { text in await gate.wait(); return imported(text) }
        let drafts = RecipeImportDrafts(link: "https://example.com/kept", text: "Kept text")
        let preparation = RecipeImportPreparation(start: .text, drafts: drafts, reader: source)
        preparation.importDraft(preparation.drafts.text, recipes: [])
        try await until { gate.entered }
        preparation.cancel()
        gate.release()
        try await until { gate.returned }
        for _ in 0..<5 { await Task.yield() }
        try expect(preparation.drafts == drafts && doneTitle(preparation) == nil, "Dismissal keeps typed drafts and ignores late reading")
    }
}
