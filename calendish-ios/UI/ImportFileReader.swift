import Foundation

/// File providers can block while downloading. Keep reads and their scoped access off the UI actor.
actor ImportFileReader {
    static let shared = ImportFileReader()

    func read(_ url: URL) throws -> Data {
        try Task.checkCancellation()
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        try Task.checkCancellation()
        return data
    }
}
