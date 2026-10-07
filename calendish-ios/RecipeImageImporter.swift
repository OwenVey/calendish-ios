import Foundation
import Vision

/// Reads the text in recipe screenshots and photos on device, then parses it like pasted text.
nonisolated enum RecipeImageImporter {
    /// Images are read in order, so a recipe split across screenshots comes out whole.
    static func parse(images: [Data]) async throws -> ImportedRecipe {
        var lines: [String] = []
        for image in images {
            try Task.checkCancellation()
            lines = merged(lines, try await text(in: image).components(separatedBy: .newlines))
        }
        let text = lines.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.noText }
        return try await RecipeTextImporter.parse(text)
    }

    /// Scrolling screenshots overlap, often with a line cut off at the edge of one of them,
    /// so the earliest run of lines that ends one page and starts the next is kept only once.
    private static func merged(_ lines: [String], _ page: [String]) -> [String] {
        func same(_ a: String, _ b: String) -> Bool {
            a == b || (min(a.count, b.count) >= 10 && (a.hasPrefix(b) || b.hasPrefix(a) || a.hasSuffix(b) || b.hasSuffix(a)))
        }
        for start in lines.indices {
            let tail = lines[start...]
            guard tail.count <= page.count, zip(tail, page).allSatisfy(same), tail.contains(where: { $0.count >= 10 }) else { continue }
            let overlap = zip(tail, page).map { $0.count >= $1.count ? $0 : $1 }
            return lines[..<start] + overlap + page.dropFirst(tail.count)
        }
        return lines + page
    }

    /// One line per ingredient, step, or paragraph. Vision's paragraphs sometimes merge list items
    /// or split a wrapped step, so lines are regrouped by their bullets, numbers, and indentation.
    static func text(in image: Data) async throws -> String {
        guard let document = try await RecognizeDocumentsRequest().perform(on: image).first?.document else { return "" }
        var entries: [(text: String, x: Double, numbered: Bool)] = []
        for paragraph in document.paragraphs {
            for (index, line) in paragraph.lines.enumerated() {
                guard let text = line.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), !text.isEmpty else { continue }
                let x = line.boundingBox.origin.x
                let startsItem = text.prefixMatch(of: itemMarker) != nil
                // A wrapped line continues its paragraph, or hangs indented under a numbered step.
                let continues = !startsItem && (index > 0 || entries.last.map { $0.numbered && x > $0.x + 0.02 } ?? false)
                if continues, let last = entries.popLast() {
                    entries.append((last.text + " " + text, last.x, last.numbered))
                } else {
                    entries.append((text, x, text.prefixMatch(of: #/\d+[.)]\s/#) != nil))
                }
            }
        }
        return entries.map(\.text).joined(separator: "\n")
    }

    /// Bullets, checkboxes (often read as "]" or "["), and step numbers that start a new item.
    private static var itemMarker: Regex<Substring> { #/[•●◦▪▢☐□\]\[|\-–*]\s|\d+[.)]\s/# }

    private enum ImportError: LocalizedError {
        case noText
        var errorDescription: String? { "Couldn’t find any text in these photos." }
    }
}
