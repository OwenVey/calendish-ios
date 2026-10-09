import Foundation

nonisolated struct ImportedRecipe {
    var recipe: Recipe
    var photo: Data?
}

/// A page as it arrived, after following any redirects.
nonisolated struct LoadedPage: Sendable {
    var url: URL
    var status: Int
    var data: Data

    var isSuccess: Bool { (200..<300).contains(status) }
    var text: String? { String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) }
}

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

/// Reads the recipe metadata published by recipe sites, without guessing missing ingredients.
nonisolated enum RecipeLinkImporter {
    static func validatedURL(_ input: String) -> URL? {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Reads a recipe site's metadata, or the written recipe in an Instagram, TikTok, or YouTube post.
    /// `sharedText` is text another app shared along with the link, such as a post's caption.
    @concurrent static func fetch(_ url: URL, sharedText: String? = nil, loader: PageLoader = .network,
                      usesModel: Bool = RecipeTextImporter.modelIsAvailable) async throws -> ImportedRecipe {
        if SocialPost.Platform(url) != nil {
            return try await importPost(url, sharedText: sharedText, loader: loader, usesModel: usesModel)
        }
        let page = try await loader.load(url)
        guard page.isSuccess, let html = page.text else { throw ImportError.unavailable }
        var result = parse(html: html)
        result.recipe.recipeLink = url.absoluteString
        result.photo = await photo(at: imageURL(html: html, baseURL: page.url), loader: loader)
        try Task.checkCancellation()
        return result
    }

    // MARK: Social posts

    /// A recipe page the creator linked to usually has the full recipe, so it comes before the caption,
    /// and the two are never mixed. Either way, the post stays the recipe's source.
    private static func importPost(_ url: URL, sharedText: String?, loader: PageLoader, usesModel: Bool) async throws -> ImportedRecipe {
        let post = await SocialPost.read(url, loader: loader)
        let texts = [post?.text, sharedText].compactMap { $0.map(SocialPost.recipeText) }.filter { !$0.isEmpty }
        let links = recipeLinks(in: texts)
        for link in links.recipes {
            guard var imported = try await linkedRecipe(link, loader: loader, usesModel: usesModel) else { continue }
            imported.recipe.recipeLink = url.absoluteString
            return imported
        }
        for text in texts {
            guard var imported = try await readRecipe(in: text, usesModel: usesModel) else { continue }
            if imported.recipe.title.isEmpty { imported.recipe.title = post?.title ?? "" }
            imported.recipe.recipeLink = url.absoluteString
            imported.photo = await photo(at: post?.imageURL, loader: loader)
            try Task.checkCancellation()
            return imported
        }
        // A link that doesn't say it's the recipe is only worth trying when the caption has none.
        for link in links.others {
            guard var imported = try await linkedRecipe(link, loader: loader, usesModel: usesModel) else { continue }
            imported.recipe.recipeLink = url.absoluteString
            return imported
        }
        // Requests stopped by cancelling fail like unreadable posts, but there's no failure to show.
        try Task.checkCancellation()
        throw ImportError.noRecipe
    }

    /// Links in a caption that could be a recipe's page: those on a line mentioning a recipe, and the rest.
    private static func recipeLinks(in texts: [String]) -> (recipes: [URL], others: [URL]) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return ([], []) }
        var recipes: [URL] = []
        var others: [URL] = []
        for line in texts.flatMap({ $0.components(separatedBy: .newlines) }) {
            for match in detector.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let link = match.url, let url = validatedURL(link.absoluteString), SocialPost.Platform(url) == nil,
                      !isShop(url), !recipes.contains(url), !others.contains(url) else { continue }
                if line.localizedCaseInsensitiveContains("recipe") { recipes.append(url) } else { others.append(url) }
            }
        }
        return (Array(recipes.prefix(2)), Array(others.prefix(2)))
    }

    private static func isShop(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return ["amazon.", "amzn.", "linktr.ee", "ltk.app", "liketk.it", "shopmy.us", "patreon.com", "facebook.com", "pinterest.", "spotify.com", "music.apple.com"]
            .contains { host.contains($0) }
    }

    /// A linked page's recipe: its recipe metadata, or the recipe in its text when it has none.
    private static func linkedRecipe(_ url: URL, loader: PageLoader, usesModel: Bool) async throws -> ImportedRecipe? {
        guard let page = try? await loader.load(url), page.isSuccess, let html = page.text else { return nil }
        let metadata = parse(html: html)
        var imported: ImportedRecipe
        if !metadata.recipe.ingredients.isEmpty || !metadata.recipe.steps.isEmpty {
            imported = metadata
        } else {
            guard let fromText = try await readRecipe(in: readableText(html: html), usesModel: usesModel) else { return nil }
            imported = fromText
            if imported.recipe.title.isEmpty { imported.recipe.title = metadata.recipe.title }
        }
        imported.photo = await photo(at: imageURL(html: html, baseURL: page.url), loader: loader)
        try Task.checkCancellation()
        return imported
    }

    /// A page's visible text, a line per block, without scripts, styles, and site navigation.
    private static func readableText(html: String) -> String {
        let visible = html
            .replacingOccurrences(of: "(?is)<(script|style|noscript|svg|nav|header|footer|form)\\b.*?</\\1\\s*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</(p|div|li|h[1-6]|tr|section|article)\\s*>", with: "\n", options: .regularExpression)
        return plainText(visible).components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    /// The recipe in some text, or nil when there isn't one. Cancelling still stops the import.
    private static func readRecipe(in text: String, usesModel: Bool) async throws -> ImportedRecipe? {
        do {
            return try await RecipeTextImporter.parse(text, usesModel: usesModel)
        } catch let error as CancellationError {
            throw error
        } catch {
            return nil
        }
    }

    private static func photo(at url: URL?, loader: PageLoader) async -> Data? {
        guard let url, let page = try? await loader.load(url), page.isSuccess, page.data.count <= 15_000_000 else { return nil }
        return page.data
    }

    static func parse(html: String) -> ImportedRecipe {
        let object = recipeObject(html: html) ?? [:]
        let prep = minutes(object["prepTime"])
        let cook = minutes(object["cookTime"])
        let total = minutes(object["totalTime"])
        let categories = list(object["recipeCategory"])
        let tags = list(object["recipeCuisine"]) + list(object["keywords"])
        let title = clean(strings(object["name"]).first ?? meta("og:title", html: html) ?? captures("<title[^>]*>([\\s\\S]*?)</title>", in: html).first ?? "")
        let recipe = Recipe(title: title,
                            summary: clean(strings(object["description"]).first ?? meta("description", html: html) ?? meta("og:description", html: html) ?? ""),
                            prepMinutes: prep, cookMinutes: cook > 0 ? cook : max(0, total - prep),
                            servings: servings(object["recipeYield"]) ?? PreferenceKey.servingsForNewRecipes,
                            tags: tags.reduce(into: []) { if !$0.contains($1) && !categories.contains($1) { $0.append($1) } },
                            symbol: "fork.knife",
                            ingredients: strings(object["recipeIngredient"]).map { clean($0) }.filter { !$0.isEmpty }.map { Ingredient(text: $0) },
                            steps: instructions(object["recipeInstructions"]),
                            // Sites use their own labels, like "Main Course"; keep only the ones that are a category here.
                            category: categories.lazy.compactMap(RecipeCategory.init(matching:)).first,
                            yieldText: yieldText(object["recipeYield"]))
        return ImportedRecipe(recipe: recipe)
    }

    private static func recipeObject(html: String) -> [String: Any]? {
        for script in captures("<script\\b[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>", in: html) {
            if let data = script.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data), let recipe = findRecipe(json) { return recipe }
        }
        return nil
    }

    private static func findRecipe(_ value: Any) -> [String: Any]? {
        if let array = value as? [Any] { return array.compactMap { findRecipe($0) }.first }
        guard let object = value as? [String: Any] else { return nil }
        if strings(object["@type"]).contains(where: { $0.components(separatedBy: "/").last == "Recipe" }) { return object }
        return object.values.compactMap { findRecipe($0) }.first
    }

    private static func instructions(_ value: Any?) -> [String] {
        if let array = value as? [Any] { return array.flatMap { instructions($0) } }
        if let object = value as? [String: Any] {
            if let items = object["itemListElement"] { return instructions(items) }
            return instructions(object["text"] ?? object["name"])
        }
        guard let text = value as? String else { return [] }
        return text.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</li>", with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines).map { clean($0) }.filter { !$0.isEmpty }
    }

    private static func strings(_ value: Any?) -> [String] {
        if let text = value as? String { return [text] }
        if let number = value as? NSNumber { return [number.stringValue] }
        if let array = value as? [Any] { return array.flatMap { strings($0) } }
        return []
    }

    private static func minutes(_ value: Any?) -> Int {
        guard let text = value as? String else { return 0 }
        let parts = captures("([0-9]+(?:\\.[0-9]+)?[DHMS])", in: text.uppercased())
        let seconds = parts.reduce(0.0) { total, part in
            let number = Double(part.dropLast()) ?? 0
            let multiplier: Double = part.last == "D" ? 86400 : part.last == "H" ? 3600 : part.last == "M" ? 60 : 1
            return total + number * multiplier
        }
        return Int(ceil(seconds / 60))
    }

    private static func servings(_ value: Any?) -> Int? {
        if let object = value as? [String: Any] { return servings(object["value"]) }
        for text in strings(value) {
            if let number = captures("([0-9]+)", in: text).first.flatMap(Int.init), number > 0 { return number }
        }
        return nil
    }

    /// A descriptive yield like "24 cookies", skipping values that only restate the servings count.
    private static func yieldText(_ value: Any?) -> String? {
        if let object = value as? [String: Any] {
            return yieldText((strings(object["value"]) + strings(object["unitText"])).joined(separator: " "))
        }
        return strings(value).map { clean($0) }
            .filter { !$0.isEmpty && $0.wholeMatch(of: /(?i)(serves|makes|yield:?)?\s*[0-9]+(\s*-\s*[0-9]+)?\s*(servings?|people|persons?|portions?)?/) == nil }
            .max { $0.count < $1.count }
    }

    /// Comma-separated or repeated values, cleaned and without blanks.
    private static func list(_ value: Any?) -> [String] {
        strings(value).flatMap { $0.components(separatedBy: ",") }.map { clean($0) }.filter { !$0.isEmpty }
    }

    static func imageURL(html: String, baseURL: URL) -> URL? {
        func imageString(_ value: Any?) -> String? {
            if let text = value as? String { return text }
            if let array = value as? [Any] { return array.compactMap { imageString($0) }.first }
            if let object = value as? [String: Any] { return imageString(object["url"] ?? object["contentUrl"]) }
            return nil
        }
        guard let text = imageString(recipeObject(html: html)?["image"]) ?? meta("og:image", html: html),
              let url = URL(string: clean(text), relativeTo: baseURL)?.absoluteURL,
              validatedURL(url.absoluteString) != nil else { return nil }
        return url
    }

    static func meta(_ name: String, html: String) -> String? {
        for tag in captures("(<meta\\b[^>]*>)", in: html) {
            let attributes = ["name", "property"].flatMap { captures("\\b\($0)\\s*=\\s*[\"']([^\"']*)[\"']", in: tag) }
            if attributes.contains(where: { $0.lowercased() == name.lowercased() }) {
                return captures("\\bcontent\\s*=\\s*[\"']([\\s\\S]*?)[\"']", in: tag).first
            }
        }
        return nil
    }

    static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func clean(_ text: String) -> String {
        plainText(text).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text without its tags and HTML entities, keeping line breaks.
    static func plainText(_ html: String) -> String {
        var result = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for entity in captures("(&#(?:x[0-9a-f]+|[0-9]+);)", in: result) {
            let hex = entity.lowercased().hasPrefix("&#x")
            let digits = entity.dropFirst(hex ? 3 : 2).dropLast()
            if let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(value) {
                result = result.replacingOccurrences(of: entity, with: String(scalar))
            }
        }
        for (entity, replacement) in [("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private enum ImportError: LocalizedError {
        case unavailable
        case noRecipe
        var errorDescription: String? {
            switch self {
            case .unavailable: "Couldn’t read this page. Check the link and try again."
            case .noRecipe: "Couldn’t get a recipe from this link."
            }
        }
    }
}
