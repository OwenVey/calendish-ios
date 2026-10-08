import Foundation

struct ImportedRecipe {
    var recipe: Recipe
    var photo: Data?
}

/// Reads the recipe metadata published by recipe sites, without guessing missing ingredients.
enum RecipeLinkImporter {
    static func validatedURL(_ input: String) -> URL? {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func fetch(_ url: URL) async throws -> ImportedRecipe {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unavailable
        }
        var result = parse(html: html)
        result.recipe.recipeLink = url.absoluteString
        if let image = imageURL(html: html, baseURL: response.url ?? url) {
            var imageRequest = URLRequest(url: image)
            imageRequest.timeoutInterval = 10
            if let (photo, response) = try? await URLSession.shared.data(for: imageRequest),
               let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
               photo.count <= 15_000_000 {
                result.photo = photo
            }
        }
        try Task.checkCancellation()
        return result
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
                            category: categories.isEmpty ? nil : categories.joined(separator: ", "),
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

    private static func imageURL(html: String, baseURL: URL) -> URL? {
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

    private static func meta(_ name: String, html: String) -> String? {
        for tag in captures("(<meta\\b[^>]*>)", in: html) {
            let attributes = ["name", "property"].flatMap { captures("\\b\($0)\\s*=\\s*[\"']([^\"']*)[\"']", in: tag) }
            if attributes.contains(where: { $0.lowercased() == name.lowercased() }) {
                return captures("\\bcontent\\s*=\\s*[\"']([\\s\\S]*?)[\"']", in: tag).first
            }
        }
        return nil
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
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
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum ImportError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Couldn’t read this page. Check the link and try again." }
    }
}
