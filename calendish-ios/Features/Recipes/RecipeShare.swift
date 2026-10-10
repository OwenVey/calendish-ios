import Foundation

/// A recipe written out for sending outside the app, at the servings and units the cook is viewing.
/// The text and the rendered card read from the same lines, so they always agree.
struct RecipeShare {
    /// A time or amount shown as a value over its label on the card, and as one phrase in the text.
    struct Fact {
        let value: String
        let label: String
        let phrase: String
    }

    static let signature = "Shared from Calendish"
    /// How much of a long recipe the card shows before pointing to the full text, so it stays readable.
    static let cardIngredientLimit = 16
    static let cardStepLimit = 6

    let recipe: Recipe
    let servings: Int
    let units: MeasurementPreference

    /// How far the ingredients scale from the servings the recipe was written for.
    var scale: Double { servings != recipe.servings && recipe.servings > 0 ? Double(servings) / Double(recipe.servings) : 1 }
    /// The summary, or nil when the recipe has none worth showing.
    var summary: String? {
        let summary = recipe.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }
    var sourceURL: URL? { recipe.recipeLink.flatMap(RecipeLinkImporter.validatedURL) }

    var ingredientLines: [String] { recipe.ingredients.map { $0.display(scale: scale, units: units) } }
    var steps: [String] { recipe.steps.map { Ingredient.convertTemperatures(in: $0, to: units) } }
    var yieldText: String? { recipe.yieldText.map { Ingredient.scale($0, by: scale) } }

    /// Prep, cook, and serving facts, leaving out what the recipe doesn't give.
    var facts: [Fact] {
        var facts: [Fact] = []
        if recipe.prepMinutes > 0 { facts.append(Fact(value: "\(recipe.prepMinutes) min", label: "Prep", phrase: "Prep \(recipe.prepMinutes) min")) }
        if recipe.cookMinutes > 0 { facts.append(Fact(value: "\(recipe.cookMinutes) min", label: "Cook", phrase: "Cook \(recipe.cookMinutes) min")) }
        if servings > 0 { facts.append(Fact(value: "\(servings)", label: servings == 1 ? "Serving" : "Servings", phrase: InterfaceCopy.servings(servings))) }
        if let yieldText { facts.append(Fact(value: yieldText, label: "Makes", phrase: "Makes \(yieldText)")) }
        return facts
    }

    var text: String {
        var sections = [recipe.title]
        if let summary { sections.append(summary) }
        if !facts.isEmpty { sections.append(facts.map(\.phrase).joined(separator: " · ")) }
        if !ingredientLines.isEmpty {
            sections.append((["Ingredients"] + ingredientLines.map { "• \($0)" }).joined(separator: "\n"))
        }
        if !steps.isEmpty {
            sections.append((["Steps"] + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }).joined(separator: "\n"))
        }
        if let sourceURL {
            sections.append("Source: \(sourceURL.absoluteString)")
        }
        sections.append(Self.signature)
        return sections.joined(separator: "\n\n")
    }
}
