import Foundation
import PDFKit

/// Reads recipe PDFs, from saved web pages to scans. Pages with text use it exactly, regrouped by layout,
/// and scanned pages are rendered and read like a photo.
nonisolated enum RecipePDFImporter {
    static func text(in data: Data, pageLimit: Int = 10) async throws -> String {
        guard let document = PDFDocument(data: data) else { throw ImportError.unreadable }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, pageLimit) {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            if let text = text(of: page) {
                pages.append(text)
            } else if let image = render(page) {
                pages.append(try await RecipeImageImporter.text(in: image))
            }
        }
        let text = pages.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.noText }
        return text
    }

    /// PDF text breaks at every wrapped line, so lines are split into paragraphs at wider gaps and column
    /// changes, then regrouped like recognized text. Nil when the page has no text, as in a scan.
    private static func text(of page: PDFPage) -> String? {
        guard let selection = page.selection(for: page.bounds(for: .mediaBox)),
              (selection.string ?? "").contains(where: \.isLetter) else { return nil }
        let width = page.bounds(for: .mediaBox).width
        var paragraphs: [[RecipeImageImporter.TextLine]] = []
        var previous: CGRect?
        for line in selection.selectionsByLine() {
            let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let bounds = line.bounds(for: page)
            guard !text.isEmpty, bounds.height > 0 else { continue }
            // PDF coordinates grow upward, so a line that sits higher than the last one starts a new column.
            let startsParagraph = previous.map { bounds.maxY > $0.maxY || $0.minY - bounds.maxY > 0.6 * bounds.height } ?? true
            if startsParagraph || paragraphs.isEmpty { paragraphs.append([]) }
            paragraphs[paragraphs.count - 1].append(.init(text: text, left: bounds.minX / width, right: bounds.maxX / width))
            previous = bounds
        }
        return RecipeImageImporter.regrouped(paragraphs)
    }

    /// Draws a page on white at about 2× so small print stays legible to text recognition.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, 2400 / max(bounds.width, bounds.height))
        guard let context = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    enum ImportError: LocalizedError {
        case unreadable, noText
        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn’t open this PDF. Choose another file."
            case .noText: "No readable text found in this PDF. Try a clearer scan or paste the recipe text."
            }
        }
    }
}
