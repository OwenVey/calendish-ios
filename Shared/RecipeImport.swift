import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Something a recipe can be imported from. Transferable, so the same type loads from paste, drag and drop,
/// and the share extension, whichever form the other app offers.
nonisolated enum RecipeImport: Sendable {
    /// A link, with any text shared along with it, such as a post's caption.
    case link(URL, text: String? = nil)
    case text(String)
    case images([Data])
    case pdf(Data)

    /// Text that is only a web address is a link.
    static func from(text: String) -> RecipeImport {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false {
            return .link(url)
        }
        return .text(text)
    }

    /// The most useful of several items shared together: a PDF, then images (in order, up to 10),
    /// then a link over plain text. Apps often share a link along with a page's title or a post's caption,
    /// so that text comes along with the link.
    static func combined(_ items: [RecipeImport]) -> RecipeImport? {
        if let pdf = items.first(where: { if case .pdf = $0 { true } else { false } }) { return pdf }
        let images = items.flatMap { item -> [Data] in if case .images(let images) = item { images } else { [] } }
        if !images.isEmpty { return .images(Array(images.prefix(10))) }
        let texts = items.compactMap { item -> String? in if case .text(let text) = item { text } else { nil } }
        if let url = items.lazy.compactMap({ item -> URL? in if case .link(let url, _) = item { url } else { nil } }).first {
            return .link(url, text: texts.isEmpty ? nil : texts.joined(separator: "\n\n"))
        }
        return items.first
    }
}

nonisolated extension RecipeImport: Transferable {
    // Earlier representations win when another app offers several, as Safari does with a page's link and title.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .pdf) { received in .pdf(try Data(contentsOf: received.file)) }
        DataRepresentation(importedContentType: .image) { data in .images([data]) }
        ProxyRepresentation { (url: URL) in from(text: url.absoluteString) }
        ProxyRepresentation { (text: String) in from(text: text) }
    }
}
