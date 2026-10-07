import Foundation

/// Recipes shared to Calendish from other apps. The share extension saves them in the App Group,
/// and the app imports them the next time it's open, one at a time.
nonisolated enum SharedInbox {
    static let appGroup = "group.owenvey.calendish-ios"

    private struct Manifest: Codable {
        var kind: String
        var value: String?
        var fileCount = 0
    }

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Inbox", directoryHint: .isDirectory)
    }

    static func save(_ item: RecipeImport) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        // Sorting by name keeps shares in order, and the manifest is written last so a half-saved share is never read.
        let folder = directory.appending(path: "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: Manifest
        switch item {
        case .link(let url): manifest = Manifest(kind: "link", value: url.absoluteString)
        case .text(let text): manifest = Manifest(kind: "text", value: text)
        case .images(let images):
            for (index, image) in images.enumerated() { try image.write(to: folder.appending(path: "\(index)")) }
            manifest = Manifest(kind: "images", fileCount: images.count)
        case .pdf(let pdf):
            try pdf.write(to: folder.appending(path: "0"))
            manifest = Manifest(kind: "pdf", fileCount: 1)
        }
        try JSONEncoder().encode(manifest).write(to: folder.appending(path: "manifest.json"), options: .atomic)
    }

    /// The oldest share, left in the inbox until `remove` so it isn't lost if it never gets shown.
    /// Shares that can't be read are discarded.
    static func next() -> (id: String, item: RecipeImport)? {
        guard let directory,
              let folders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")) else { continue }
            let id = folder.lastPathComponent
            guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { remove(id); continue }
            let files = (0..<manifest.fileCount).compactMap { try? Data(contentsOf: folder.appending(path: "\($0)")) }
            switch manifest.kind {
            case "link": if let url = manifest.value.flatMap(URL.init(string:)) { return (id, .link(url)) }
            case "text": if let text = manifest.value { return (id, .text(text)) }
            case "images": if !files.isEmpty { return (id, .images(files)) }
            case "pdf": if let pdf = files.first { return (id, .pdf(pdf)) }
            default: break
            }
            remove(id)
        }
        return nil
    }

    static func remove(_ id: String) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: id, directoryHint: .isDirectory))
    }
}
