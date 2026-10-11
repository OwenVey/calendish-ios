import Foundation

/// Compares recipe links by the page they lead to, so the same recipe shared twice is recognized
/// despite tracking parameters, `www.`, trailing slashes, or a short YouTube link.
nonisolated enum RecipeSourceLink {
    /// Query parameters that only say where a link was shared from.
    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "igsh", "igshid", "si", "feature", "ref", "ref_src", "_r", "_t", "share", "mibextid",
        "is_from_webapp", "sender_device", "sender_web_id", "is_copy_url", "pp",
    ]

    /// The parts of a link that identify its page, or nil for anything that isn't a web link.
    static func key(_ link: String) -> String? {
        guard let url = RecipeLinkImporter.validatedURL(link),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var host = components.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        var query = (components.queryItems ?? []).filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
        }

        // One YouTube video has several kinds of links.
        if host == "youtu.be" || host == "youtube.com" {
            let video = host == "youtu.be" ? String(path.dropFirst())
                : path.hasPrefix("/shorts/") ? String(path.dropFirst("/shorts/".count))
                : query.first { $0.name == "v" }?.value
            if let video, !video.isEmpty {
                host = "youtube.com"; path = "/watch"; query = [URLQueryItem(name: "v", value: video)]
            }
        }
        // As does one Instagram post.
        if host == "instagram.com", let range = path.range(of: #"^/(reels?|p|tv)/"#, options: .regularExpression) {
            path.replaceSubrange(range, with: "/p/")
        }

        components.host = host
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        components.scheme = nil
        components.fragment = nil
        components.port = nil
        return components.string
    }

    /// A saved recipe imported from the same page as `url`.
    static func recipe(from url: URL, in recipes: [Recipe]) -> Recipe? {
        guard let key = key(url.absoluteString) else { return nil }
        return recipes.first { $0.recipeLink.flatMap(self.key) == key }
    }
}
