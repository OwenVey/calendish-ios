import Foundation

/// How importing reaches the web. Tests replace it with recorded pages.
nonisolated struct PageLoader: Sendable {
    var load: @Sendable (URL) async throws -> LoadedPage

    static let network = PageLoader { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Facebook asks apps it doesn't recognize to log in, but shows public videos to Safari.
        if SocialPost.Platform(url) == .facebook {
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                             forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return LoadedPage(url: http?.url ?? url, status: http?.statusCode ?? 0, data: data)
    }
}
