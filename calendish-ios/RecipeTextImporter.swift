import Foundation
import FoundationModels

/// Turns recipe text copied from a web page, note, or message into a draft recipe.
/// Uses the on-device language model when it's available, and recognizes common recipe headings otherwise.
enum RecipeTextImporter {
    static func parse(_ text: String) async throws -> ImportedRecipe {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromHeadings = parseHeadings(text)
        let hasLists = !fromHeadings.ingredients.isEmpty && !fromHeadings.steps.isEmpty
        if SystemLanguageModel.default.isAvailable {
            do {
                if var recipe = try await parseWithModel(text) {
                    // Lines under clear headings are exact, while the model can skip or reword them.
                    if hasLists {
                        recipe.ingredients = fromHeadings.ingredients
                        recipe.steps = fromHeadings.steps
                    }
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
        @Guide(description: "Whether the text contains a recipe with its ingredients. False for anything else, such as a message or a list of plans.")
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
        @Guide(description: "Each ingredient line exactly as written, with its quantity and unit.")
        var ingredients: [String]
        @Guide(description: "Every instruction step in order, including preheating and preparation, without step numbers.")
        var steps: [String]
    }

    private static func parseWithModel(_ text: String) async throws -> Recipe? {
        let session = LanguageModelSession(instructions: """
            Extract the recipe from text a person copied from a website, note, or message. \
            The text may also contain stories, ads, navigation, ratings, nutrition facts, and comments: ignore them. \
            Copy every ingredient and step faithfully. Never skip, invent, or change ingredients or quantities.
            """)
        let response = try await session.respond(to: focused(text), generating: ParsedRecipe.self, options: GenerationOptions(samplingMode: .greedy))
        let parsed = response.content
        let ingredients = parsed.ingredients.map(cleanLine).filter { !$0.isEmpty }
        let steps = parsed.steps.map(cleanLine).filter { !$0.isEmpty }
        guard parsed.containsRecipe, !ingredients.isEmpty, !steps.isEmpty, isGrounded(ingredients, in: text) else { return nil }
        let yield = parsed.yield.trimmingCharacters(in: .whitespacesAndNewlines)
        return Recipe(title: parsed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                      summary: parsed.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                      prepMinutes: max(0, parsed.prepMinutes), cookMinutes: max(0, parsed.cookMinutes),
                      servings: parsed.servings > 0 ? parsed.servings : 4,
                      tags: [], symbol: "fork.knife",
                      ingredients: ingredients.map { Ingredient(text: $0) }, steps: steps,
                      yieldText: yield.isEmpty ? nil : yield)
    }

    /// The model can invent a whole recipe from unrelated text, so most ingredients must share a word with it.
    private static func isGrounded(_ ingredients: [String], in text: String) -> Bool {
        let source = text.lowercased()
        let found = ingredients.filter { line in
            line.lowercased().split(whereSeparator: { !$0.isLetter }).contains { $0.count >= 4 && source.contains($0) }
        }
        return found.count * 2 >= ingredients.count
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
    private static let stepsHeading = #/(?i)(instructions|directions|method|preparation|steps|how to make( it)?|to make)/#
    private static let endHeading = #/(?i)(notes?|recipe notes|tips|nutrition( facts| information)?|equipment|video|did you make this.*)/#

    private static func isHeading(_ line: String, _ pattern: Regex<some Any>) -> Bool {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return line.count < 40 && line.wholeMatch(of: pattern) != nil
    }

    private static func parseHeadings(_ text: String) -> Recipe {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.wholeMatch(of: #/(?i)advertisement|sponsored|ad/#) == nil }
        let ingredientsStart = lines.firstIndex { isHeading($0, ingredientsHeading) }
        let stepsStart = lines.indices.first { $0 > (ingredientsStart ?? -1) && isHeading(lines[$0], stepsHeading) }
        var ingredients: [String] = []
        var steps: [String] = []
        if let ingredientsStart, let stepsStart {
            ingredients = lines[(ingredientsStart + 1)..<stepsStart].filter { !$0.hasSuffix(":") }.map(cleanLine)
            let end = lines.indices.first { $0 > stepsStart && isHeading(lines[$0], endHeading) } ?? lines.endIndex
            steps = lines[(stepsStart + 1)..<end].map(cleanLine)
        }
        // The first short line above the ingredients that isn't a sentence or page chrome like "Jump to Recipe".
        let title = lines[..<(ingredientsStart ?? lines.endIndex)].first {
            $0.count <= 80 && !".!?:".contains($0.last ?? ".") && $0.firstMatch(of: #/(?i)\b(jump to|skip to|print|pin)\b/#) == nil
        } ?? ""
        let prep = minutes(labeled: #/(?i)prep(aration)? time/#, in: lines)
        let cook = minutes(labeled: #/(?i)cook(ing)? time/#, in: lines)
        let total = minutes(labeled: #/(?i)total time/#, in: lines)
        let servings = text.firstMatch(of: #/(?i)(serves|servings|yield)\s*:?\s*(\d+)/#).flatMap { Int($0.output.2) }
        return Recipe(title: title, summary: "", prepMinutes: prep, cookMinutes: cook > 0 ? cook : max(0, total - prep),
                      servings: servings ?? 4, tags: [], symbol: "fork.knife",
                      ingredients: ingredients.filter { !$0.isEmpty }.map { Ingredient(text: $0) },
                      steps: steps.filter { !$0.isEmpty })
    }

    /// A duration after a label, on the same line ("Prep Time: 15 mins") or the next ("Prep Time" / "15 minutes").
    private static func minutes(labeled label: Regex<some Any>, in lines: [String]) -> Int {
        guard let index = lines.firstIndex(where: { $0.prefixMatch(of: label) != nil }) else { return 0 }
        let value = lines[index].replacing(label, with: "", maxReplacements: 1) + " " + (index + 1 < lines.count ? lines[index + 1] : "")
        let hours = value.firstMatch(of: #/(?i)(\d+)\s*(h|hrs?|hours?)\b/#).flatMap { Int($0.output.1) } ?? 0
        let minutes = value.firstMatch(of: #/(?i)(\d+)\s*(m|mins?|minutes?)\b/#).flatMap { Int($0.output.1) } ?? 0
        return hours * 60 + minutes
    }

    /// Drops bullets, checkboxes, and step numbers that come along when copying from a web page.
    nonisolated private static func cleanLine(_ line: String) -> String {
        line.replacing(#/^\s*([▢☐□•●◦▪\-–*\]\[|]|(?i:step)\s*\d+[.):]?|\d+[.):](?!\d))\s*/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum ImportError: LocalizedError {
        case unrecognized
        var errorDescription: String? { "Couldn’t find a recipe in this text. Make sure it includes the ingredients and instructions." }
    }
}
