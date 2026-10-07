import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Something a recipe can be imported from. Transferable, so the same type loads from paste, drag and drop,
/// and the share extension, whichever form the other app offers.
nonisolated enum RecipeImport: Sendable {
    case link(URL)
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
    /// then a link over plain text, since apps often share a page's link along with its title.
    static func combined(_ items: [RecipeImport]) -> RecipeImport? {
        if let pdf = items.first(where: { if case .pdf = $0 { true } else { false } }) { return pdf }
        let images = items.flatMap { item -> [Data] in if case .images(let images) = item { images } else { [] } }
        if !images.isEmpty { return .images(Array(images.prefix(10))) }
        if let link = items.first(where: { if case .link = $0 { true } else { false } }) { return link }
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
