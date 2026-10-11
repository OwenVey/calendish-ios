import Foundation
import FoundationModels

/// Turns recipe text copied from a web page, note, or message into a draft recipe.
/// Uses the on-device language model when it's available, and recognizes common recipe headings otherwise.
enum RecipeTextImporter {
    nonisolated static var modelIsAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// A recipe needs ingredients or instructions; it doesn't need both.
    static func parse(_ text: String, usesModel: Bool = modelIsAvailable) async throws -> ImportedRecipe {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromHeadings = parseHeadings(text)
        let hasLists = !fromHeadings.ingredients.isEmpty || !fromHeadings.steps.isEmpty
        if usesModel {
            do {
                if var recipe = try await parseWithModel(text) {
                    // Lines under clear headings are exact, while the model can skip or reword them.
                    if !fromHeadings.ingredients.isEmpty { recipe.ingredients = fromHeadings.ingredients }
                    if !fromHeadings.steps.isEmpty { recipe.steps = fromHeadings.steps }
                    return ImportedRecipe(recipe: recipe)
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                // Too long for the model's context, a guardrail, or a busy model: fall back to headings.
            }
        }
        guard hasLists else { throw ImportError.unrecognized }
        return ImportedRecipe(recipe: fromHeadings)
    }

    // MARK: On-device model

    @Generable
    nonisolated struct ParsedRecipe {
        // Generated first, so the model can decline before it starts writing ingredients.
        @Guide(description: "Whether the text contains a recipe's ingredients or cooking instructions. False for anything else, such as a message, a list of plans, or only a dish's name.")
        var containsRecipe: Bool
        @Guide(description: "The recipe's name.")
        var title: String
        @Guide(description: "A one or two sentence description of the dish taken from the text, not its servings or times, or empty.")
        var summary: String
        @Guide(description: "How many people the recipe serves, or 0 if not stated.")
        var servings: Int
        @Guide(description: "What the recipe makes when it's counted in items rather than servings, such as \"24 cookies\", or empty.")
        var yield: String
        @Guide(description: "Preparation time in minutes, or 0 if not stated.")
        var prepMinutes: Int
        @Guide(description: "Cooking time in minutes, or 0 if not stated.")
        var cookMinutes: Int
        @Guide(description: "Each ingredient line exactly as written, with its quantity and unit, or none if the text doesn't list them.")
        var ingredients: [String]
        @Guide(description: "Every instruction step in order, including preheating and preparation, without step numbers, or none if the text doesn't give them.")
        var steps: [String]
    }

    private static func parseWithModel(_ text: String) async throws -> Recipe? {
        let session = LanguageModelSession(instructions: """
            Extract the recipe from text a person copied from a website, note, or message. \
            The text may also contain stories, ads, navigation, ratings, nutrition facts, and comments: ignore them. \
            Copy every ingredient and step faithfully. Never skip, invent, or change ingredients or quantities. \
            If the text has several recipes, extract only the first. Leave out anything the text doesn't state.
            """)
        let response = try await session.respond(to: focused(text), generating: ParsedRecipe.self, options: GenerationOptions(samplingMode: .greedy))
        let parsed = response.content
        guard parsed.containsRecipe else { return nil }
        let source = SourceText(text)
        let ingredients = parsed.ingredients.map(cleanLine).filter { !$0.isEmpty }
        let steps = parsed.steps.map(cleanLine).filter { !$0.isEmpty }
        let statedIngredients = ingredients.filter { source.states($0, wordShare: 0.5) }
        let statedSteps = steps.filter { source.states($0, wordShare: 0.6) }
        // A model that made up much of the recipe can't be trusted for the rest of it either.
        let lines = ingredients.count + steps.count
        let stated = statedIngredients.count + statedSteps.count
        guard stated > 0, stated * 4 >= lines * 3 else { return nil }
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let yield = parsed.yield.trimmingCharacters(in: .whitespacesAndNewlines)
        return Recipe(title: source.states(title, wordShare: 0.5) ? title : "",
                      summary: source.states(parsed.summary, wordShare: 0.6) ? parsed.summary.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                      prepMinutes: source.states(minutes: parsed.prepMinutes) ? parsed.prepMinutes : 0,
                      cookMinutes: source.states(minutes: parsed.cookMinutes) ? parsed.cookMinutes : 0,
                      servings: source.states(parsed.servings) ? parsed.servings : PreferenceKey.servingsForNewRecipes,
                      tags: [], symbol: "fork.knife",
                      ingredients: statedIngredients.map { Ingredient(text: $0) }, steps: statedSteps,
                      yieldText: yield.isEmpty || !source.states(yield, wordShare: 0.5) ? nil : yield)
    }

    /// The words and numbers in the text the model read. The model can make up a recipe, or quantities and steps
    /// in a real one, so its output is kept only where the text says the same.
    private struct SourceText {
        private let words: Set<String>
        private let numbers: Set<String>

        init(_ text: String) {
            let text = Self.normalized(text)
            words = Set(Self.words(in: text))
            numbers = Set(Self.numbers(in: text))
        }

        /// Every number in the line is in the text, along with this share of its words.
        func states(_ line: String, wordShare: Double) -> Bool {
            let line = Self.normalized(line)
            let lineNumbers = Self.numbers(in: line)
            guard lineNumbers.allSatisfy(numbers.contains) else { return false }
            let lineWords = Self.words(in: line)
            guard !lineWords.isEmpty else { return !lineNumbers.isEmpty }
            let found = lineWords.filter(words.contains).count
            return found > 0 && Double(found) >= Double(lineWords.count) * wordShare
        }

        /// A positive number the text mentions, like servings or minutes.
        func states(_ number: Int) -> Bool { number > 0 && numbers.contains(String(number)) }

        /// A duration the text gives in minutes, hours, or both, like "1 hour 30 minutes" for 90.
        func states(minutes: Int) -> Bool {
            guard minutes > 0 else { return false }
            if states(minutes) { return true }
            return minutes >= 60 && (1...(minutes / 60)).contains { hours in
                states(hours) && (minutes == hours * 60 || states(minutes - hours * 60))
            }
        }

        private static func normalized(_ text: String) -> String {
            var text = text.lowercased()
            for (fraction, digits) in ["½": " 1/2", "⅓": " 1/3", "⅔": " 2/3", "¼": " 1/4", "¾": " 3/4", "⅛": " 1/8"] {
                text = text.replacingOccurrences(of: fraction, with: digits)
            }
            return text
        }

        private static func numbers(in text: String) -> [String] {
            text.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).map { String(Int($0) ?? 0) }
        }

        /// Words of three letters or more, without plural endings, so "potato" matches "potatoes" and "sauce" matches "sauces".
        private static func words(in text: String) -> [String] {
            text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 }.map { word in
                var word = Substring(word)
                if word.hasSuffix("s"), word.count > 3 { word = word.dropLast() }
                if word.hasSuffix("e"), word.count > 3 { word = word.dropLast() }
                return String(word)
            }
        }
    }

    /// The model's context is small, so long pages are trimmed to the part around the ingredients.
    private static func focused(_ text: String, limit: Int = 6000) -> String {
        guard text.count > limit else { return text }
        let lines = text.components(separatedBy: .newlines)
        guard let heading = lines.firstIndex(where: { isHeading($0, ingredientsHeading) }) else { return String(text.prefix(limit)) }
        // Keep some lines above the heading for the title, servings, and times.
        let start = lines[..<heading].reversed().reduce(into: (index: heading, length: 0)) { result, line in
            guard result.length + line.count < limit / 4 else { return }
            result.length += line.count + 1
            result.index -= 1
        }.index
        return String(lines[start...].joined(separator: "\n").prefix(limit))
    }

    // MARK: Headings

    private static let ingredientsHeading = #/(?i)(ingredients?|(what )?you(’|')ll need|shopping list)/#
    private static let stepsHeading = #/(?i)(instructions|directions|method|preparation|steps|how to( make( it)?)?|to make)/#
    /// A part of the ingredients, like "For the sauce:", which can stand in for an ingredients heading.
    private static let sectionHeading = #/(?i)for the [\p{L} ]+/#
    private static let endHeading = #/(?i)(notes?|recipe notes|tips|nutrition( facts| information)?|equipment|video|did you make this.*)/#

    private static func isHeading(_ line: String, _ pattern: Regex<some Any>) -> Bool {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return line.count < 40 && line.wholeMatch(of: pattern) != nil
    }

    private static func parseHeadings(_ text: String) -> Recipe {
        // Blank lines are kept to tell where a list without a following heading ends.
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.wholeMatch(of: #/(?i)advertisement|sponsored|ad/#) == nil }
        let firstSteps = lines.firstIndex { isHeading($0, stepsHeading) }
        // Without an ingredients heading, a part like "For the sauce:" starts them, unless it's in the method.
        let ingredientsStart = lines.firstIndex { isHeading($0, ingredientsHeading) }
            ?? lines.indices.first { $0 < (firstSteps ?? lines.endIndex) && isHeading(lines[$0], sectionHeading) }
        // An ingredients heading after the method starts another recipe; only the first is imported.
        // Before the method, it's a part of the same recipe, like a pie's dough and filling.
        let methodStart = ingredientsStart.flatMap { start in lines.indices.first { $0 > start && isHeading(lines[$0], stepsHeading) } }
        let nextRecipe = methodStart.flatMap { start in lines.indices.first { $0 > start && isHeading(lines[$0], ingredientsHeading) } }
        let recipeEnd = nextRecipe.map { end in end > 0 && isTitle(lines[end - 1]) ? end - 1 : end } ?? lines.endIndex
        let stepsStart = lines.indices.first { $0 > (ingredientsStart ?? -1) && $0 < recipeEnd && isHeading(lines[$0], stepsHeading) }
        var ingredients: [String] = []
        var steps: [String] = []
        if let ingredientsStart {
            let end = stepsStart ?? listEnd(after: ingredientsStart, before: recipeEnd, in: lines)
            // Skips headings, separators, servings, and the names of parts above their own ingredients heading.
            ingredients = lines.indices[(ingredientsStart + 1)..<end]
                .filter { $0 + 1 >= end || !isHeading(lines[$0 + 1], ingredientsHeading) }
                .map { lines[$0] }
                .filter { !$0.hasSuffix(":") && !isHeading($0, ingredientsHeading) && $0.contains(where: { $0.isLetter || $0.isNumber }) && $0.wholeMatch(of: servingsLine) == nil }
                .map(cleanLine)
        }
        if let stepsStart {
            let end = lines[(stepsStart + 1)..<recipeEnd].firstIndex { endsRecipe($0) } ?? recipeEnd
            steps = lines[(stepsStart + 1)..<end].map(cleanLine)
        }
        // The first short line above the lists that isn't a sentence or page chrome like "Jump to Recipe".
        // Posts with several recipes number them, like "Recipe 1: Garlic Noodles".
        let title = (lines[..<(ingredientsStart ?? stepsStart ?? lines.endIndex)].first { isTitle($0) } ?? "")
            .replacing(#/^(?i)recipe\s*#?\d+\s*[:.\-–]\s*/#, with: "")
        let prep = minutes(labeled: #/(?i)prep(aration)? time/#, in: lines)
        let cook = minutes(labeled: #/(?i)cook(ing)? time/#, in: lines)
        let total = minutes(labeled: #/(?i)total time/#, in: lines)
        let servings = lines[..<recipeEnd].lazy.compactMap { line in
            line.firstMatch(of: #/(?i)(?:serves|servings|yield|makes)\s*:?\s*(\d+)|(\d+)\s*(?:servings|portions)\b/#).flatMap { Int($0.output.1 ?? $0.output.2 ?? "") }
        }.first
        return Recipe(title: title, summary: "", prepMinutes: prep, cookMinutes: cook > 0 ? cook : max(0, total - prep),
                      servings: servings ?? PreferenceKey.servingsForNewRecipes, tags: [], symbol: "fork.knife",
                      ingredients: ingredients.filter { !$0.isEmpty }.map { Ingredient(text: $0) },
                      steps: steps.filter { !$0.isEmpty })
    }

    private static let servingsLine = #/(?i)(for|serves|makes)?\s*\d+\s*(servings?|portions?|people)?/#
    /// Where a caption moves on from the recipe, like "Follow for more recipes".
    private static let signOff = #/(?i)^(follow\b|save (this|it|for later)\b|comment\b|share (this|with)\b|tag (a|someone|your)\b|subscribe\b|link in (my )?bio\b|(full )?recipe (is )?(in|on) (my )?(bio|blog|website)\b)/#

    private static func endsRecipe(_ line: String) -> Bool {
        isHeading(line, endHeading) || line.firstMatch(of: signOff) != nil
    }

    private static func isTitle(_ line: String) -> Bool {
        !line.isEmpty && line.count <= 80 && !".!?:".contains(line.last ?? ".") && line.firstMatch(of: #/(?i)\b(jump to|skip to|print|pin)\b/#) == nil
    }

    /// A list without a heading after it ends at a blank line, unless a subheading like "For the sauce:" continues it.
    private static func listEnd(after start: Int, before end: Int, in lines: [String]) -> Int {
        var index = start + 1
        var sawItem = false
        while index < end {
            let line = lines[index]
            if line.isEmpty {
                let next = lines[index..<end].first { !$0.isEmpty }
                if sawItem, !(next?.hasSuffix(":") ?? false) { return index }
            } else if endsRecipe(line) {
                return index
            } else if !line.hasSuffix(":") {
                sawItem = true
            }
            index += 1
        }
        return end
    }

    /// A duration after a label, on the same line ("Prep Time: 15 mins") or the next ("Prep Time" / "15 minutes").
    private static func minutes(labeled label: Regex<some Any>, in lines: [String]) -> Int {
        guard let index = lines.firstIndex(where: { $0.prefixMatch(of: label) != nil }) else { return 0 }
        let next = lines[(index + 1)...].first { !$0.isEmpty } ?? ""
        let value = lines[index].replacing(label, with: "", maxReplacements: 1) + " " + next
        let hours = value.firstMatch(of: #/(?i)(\d+)\s*(h|hrs?|hours?)\b/#).flatMap { Int($0.output.1) } ?? 0
        let minutes = value.firstMatch(of: #/(?i)(\d+)\s*(m|mins?|minutes?)\b/#).flatMap { Int($0.output.1) } ?? 0
        return hours * 60 + minutes
    }

    /// Drops bullets, checkboxes, and step numbers that come along when copying from a web page.
    private nonisolated static func cleanLine(_ line: String) -> String {
        line.replacing(#/^\s*([▢☐□•●◦▪\-–*\]\[|]|(?i:step)\s*\d+[.):]?|\d+[.):](?!\d))\s*/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum ImportError: LocalizedError {
        case unrecognized
        var errorDescription: String? { "Couldn’t find a recipe in this text. Make sure it includes the ingredients or instructions." }
    }
}
