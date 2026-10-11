import Foundation

/// What a creator wrote with an Instagram, TikTok, YouTube, or Facebook post: its caption or description, read from public pages.
/// Only written text is read, not audio, subtitles, on-screen text, or comments.
nonisolated struct SocialPost {
    enum Platform {
        case instagram, tikTok, youTube, facebook

        init?(_ url: URL) {
            let host = url.host?.lowercased() ?? ""
            func matches(_ domains: String...) -> Bool { domains.contains { host == $0 || host.hasSuffix("." + $0) } }
            if matches("instagram.com", "instagr.am") { self = .instagram }
            else if matches("tiktok.com") { self = .tikTok }
            else if matches("youtube.com", "youtu.be") { self = .youTube }
            else if matches("facebook.com", "fb.watch", "fb.com") { self = .facebook }
            else { return nil }
        }
    }

    /// The post's own title, which only some sites have, such as a YouTube video's.
    var title: String?
    var text: String
    var imageURL: URL?

    /// Reads the post, following share links. Nil when it can't be read, such as when it's private or deleted.
    static func read(_ url: URL, loader: PageLoader) async -> SocialPost? {
        switch Platform(url) {
        case .youTube: await readYouTube(url, loader: loader)
        case .instagram: await readInstagram(url, loader: loader)
        case .tikTok: await readTikTok(url, loader: loader)
        case .facebook: await readFacebook(url, loader: loader)
        case nil: nil
        }
    }

    /// The parts of a caption that can be part of a recipe: no hashtags, though numbers like "#1" stay.
    static func recipeText(_ caption: String) -> String {
        caption.replacing(#/(?m)(^|[ \t])#\p{L}[\p{L}\p{N}_]*/#) { String($0.output.1) }
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: YouTube

    /// The watch page includes the full description, unlike its preview, in the player's data.
    private static func readYouTube(_ url: URL, loader: PageLoader) async -> SocialPost? {
        guard let page = try? await loader.load(url), page.isSuccess, let html = page.text,
              let description = jsonString(named: "shortDescription", in: html) else { return nil }
        let title = RecipeLinkImporter.meta("og:title", html: html).map(RecipeLinkImporter.plainText)
        return SocialPost(title: title ?? jsonString(named: "title", in: html), text: description,
                          imageURL: RecipeLinkImporter.imageURL(html: html, baseURL: page.url))
    }

    // MARK: Instagram

    /// The post page's preview cuts long captions short, so the caption comes from the post's public embed page.
    private static func readInstagram(_ url: URL, loader: PageLoader) async -> SocialPost? {
        let shortcode: String
        if let code = instagramShortcode(url) {
            shortcode = code
        } else {
            // Share links redirect to the post.
            guard let page = try? await loader.load(url), page.isSuccess, let code = instagramShortcode(page.url) else { return nil }
            shortcode = code
        }
        guard let embed = URL(string: "https://www.instagram.com/p/\(shortcode)/embed/captioned/"),
              let page = try? await loader.load(embed), page.isSuccess, let html = page.text,
              let caption = RecipeLinkImporter.captures("<div class=\"Caption\">([\\s\\S]*?)<div class=\"CaptionComments\"", in: html).first else { return nil }
        let text = caption
            .replacingOccurrences(of: "<a class=\"CaptionUsername\"[^>]*>[\\s\\S]*?</a>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        let image = RecipeLinkImporter.captures("class=\"EmbeddedMediaImage\"[^>]*\\bsrc=\"([^\"]+)\"", in: html).first
        return SocialPost(text: RecipeLinkImporter.plainText(text), imageURL: image.flatMap { URL(string: RecipeLinkImporter.plainText($0)) })
    }

    /// The post's code in links like instagram.com/p/CODE, /reel/CODE, or /name/reel/CODE.
    private static func instagramShortcode(_ url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        // Share links, like /share/reel/CODE, have a code of their own that isn't the post's.
        guard parts.first != "share", let index = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    // MARK: TikTok

    /// The video page's data has the caption, though where depends on the page TikTok serves.
    /// TikTok's public embed details have it too, for when the page doesn't.
    private static func readTikTok(_ url: URL, loader: PageLoader) async -> SocialPost? {
        // Short links like vm.tiktok.com redirect to the video.
        let page = try? await loader.load(url)
        let videoURL = page?.url ?? url
        guard let id = RecipeLinkImporter.captures("/(?:video|photo)/([0-9]+)", in: videoURL.path).first else { return nil }
        if let page, page.isSuccess, let html = page.text,
           let script = RecipeLinkImporter.captures("<script[^>]*id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\"[^>]*>([\\s\\S]*?)</script>", in: html).first,
           let data = try? JSONSerialization.jsonObject(with: Data(script.utf8)),
           let item = object(in: data, where: { $0["id"] as? String == id && $0["desc"] is String }),
           let caption = item["desc"] as? String, !caption.isEmpty {
            return SocialPost(text: caption, imageURL: RecipeLinkImporter.imageURL(html: html, baseURL: page.url))
        }
        let canonical = "https://www.tiktok.com\(videoURL.path)"
        guard let encoded = canonical.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))),
              let oEmbedURL = URL(string: "https://www.tiktok.com/oembed?url=\(encoded)"),
              let oEmbed = try? await loader.load(oEmbedURL), oEmbed.isSuccess,
              let details = try? JSONSerialization.jsonObject(with: oEmbed.data) as? [String: Any],
              let caption = details["title"] as? String, !caption.isEmpty else { return nil }
        return SocialPost(text: caption, imageURL: (details["thumbnail_url"] as? String).flatMap(URL.init(string:)))
    }

    // MARK: Facebook

    /// The video page's description cuts long captions short, but its titles have the whole caption.
    /// Share links, like fb.watch or /share/r/, redirect to the video.
    private static func readFacebook(_ url: URL, loader: PageLoader) async -> SocialPost? {
        guard let page = try? await loader.load(url), page.isSuccess, let html = page.text else { return nil }
        // The embed link's title is "caption | creator", sometimes followed by " | Facebook".
        // The page's title starts with its views and reactions too.
        var parts: [String]
        if let title = RecipeLinkImporter.captures("<link\\b[^>]*\\btitle=\"([^\"]*)\"[^>]*application/json\\+oembed", in: html).first {
            parts = RecipeLinkImporter.plainText(title).components(separatedBy: " | ")
        } else if let title = RecipeLinkImporter.meta("og:title", html: html) {
            parts = Array(RecipeLinkImporter.plainText(title).components(separatedBy: " | ").dropFirst())
        } else {
            return nil
        }
        if parts.last == "Facebook" { parts.removeLast() }
        guard parts.count > 1 else { return nil }
        let caption = parts.dropLast().joined(separator: " | ")
        return SocialPost(text: caption, imageURL: RecipeLinkImporter.imageURL(html: html, baseURL: page.url))
    }

    // MARK: Helpers

    /// The first object in some JSON that matches, searching depth first.
    private static func object(in json: Any, where matches: ([String: Any]) -> Bool) -> [String: Any]? {
        if let object = json as? [String: Any] {
            if matches(object) { return object }
            for value in object.values { if let found = Self.object(in: value, where: matches) { return found } }
        }
        if let array = json as? [Any] {
            for value in array { if let found = object(in: value, where: matches) { return found } }
        }
        return nil
    }

    /// The first JSON string value with this name in a page's embedded data.
    private static func jsonString(named name: String, in html: String) -> String? {
        guard let literal = RecipeLinkImporter.captures("\"\(name)\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")", in: html).first,
              let data = literal.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
    }
}
