import Foundation
import Vision

/// Reads the text in recipe screenshots, photos, and scans on device, ready to parse like pasted text.
nonisolated enum RecipeImageImporter {
    /// The text of all the images, read in order so a recipe split across screenshots comes out whole.
    static func text(in images: [Data]) async throws -> String {
        var lines: [String] = []
        for image in images {
            try Task.checkCancellation()
            lines = merged(lines, try await text(in: image).components(separatedBy: .newlines))
        }
        let text = lines.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.noText }
        return text
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

    static func text(in image: Data) async throws -> String {
        text(of: try await RecognizeDocumentsRequest().perform(on: image).first?.document)
    }

    static func text(in image: CGImage) async throws -> String {
        text(of: try await RecognizeDocumentsRequest().perform(on: image).first?.document)
    }

    private static func text(of document: DocumentObservation.Container?) -> String {
        regrouped(document?.paragraphs.map { paragraph in
            paragraph.lines.map { line in
                TextLine(text: fixQuantity(line.topCandidates(1).first?.string ?? ""),
                         left: line.boundingBox.origin.x, right: line.boundingBox.origin.x + line.boundingBox.width)
            }
        } ?? [])
    }

    /// A line of text and its horizontal extent, as a fraction of the page width.
    struct TextLine {
        var text: String
        var left: Double
        var right: Double
    }

    /// One line per ingredient, step, or paragraph. Paragraphs from text recognition or PDF layout sometimes
    /// merge list items or split a wrapped step, so lines are regrouped by their bullets, numbers, and indentation.
    static func regrouped(_ paragraphs: [[TextLine]]) -> String {
        var entries: [(text: String, x: Double, numbered: Bool)] = []
        for lines in paragraphs {
            let left = lines.map(\.left).min() ?? 0
            let width = (lines.map(\.right).max() ?? 0) - left
            for (index, line) in lines.enumerated() {
                let text = line.text.trimmingCharacters(in: .whitespaces)
                // Skip blanks and page numbers.
                guard !text.isEmpty, text.wholeMatch(of: #/\d{1,4}/#) == nil else { continue }
                // A line after one that stopped short is a new item when it starts like one, as in an unbulleted ingredient list.
                let previousStoppedShort = index > 0 && lines[index - 1].right - left < 0.8 * width
                let startsItem = text.prefixMatch(of: itemMarker) != nil || (previousStoppedShort && text.prefixMatch(of: #/[\d¼½¾⅓⅔⅛\p{Lu}]/#) != nil)
                // A wrapped line continues its paragraph, or hangs indented under a numbered step.
                let continues = !startsItem && (index > 0 || entries.last.map { $0.numbered && line.left > $0.x + 0.02 } ?? false)
                if continues, let last = entries.popLast() {
                    entries.append((last.text + " " + text, last.x, last.numbered))
                } else {
                    entries.append((text, line.left, text.prefixMatch(of: #/\d+[.)]\s/#) != nil))
                }
            }
        }
        return entries.map(\.text).joined(separator: "\n")
    }

    /// OCR often drops the space in mixed numbers and before parentheses: "11/2 lb" and "1(14-oz) can".
    private static func fixQuantity(_ line: String) -> String {
        line.replacing(#/^(\d)([1-7]\/[2348])\b/#) { "\($0.output.1) \($0.output.2)" }
            .replacing(#/^(\d+)\(/#) { "\($0.output.1) (" }
    }

    /// Bullets, checkboxes (often read as "]" or "["), and step numbers that start a new item.
    private static var itemMarker: Regex<Substring> { #/[•●◦▪▢☐□\]\[|\-–*]\s|\d+[.)]\s/# }

    enum ImportError: LocalizedError {
        case noText
        var errorDescription: String? { "No readable text found. Try a clearer photo or paste the recipe text." }
    }
}
