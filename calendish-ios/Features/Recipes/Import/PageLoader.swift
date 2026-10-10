import Foundation

/// How importing reaches the web. Tests replace it with recorded pages.
nonisolated struct PageLoader: Sendable {
    var load: @Sendable (URL) async throws -> LoadedPage

    static let network = PageLoader { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return LoadedPage(url: http?.url ?? url, status: http?.statusCode ?? 0, data: data)
    }
}
