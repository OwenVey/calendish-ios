import Foundation

@main
struct RecipeLinkImporterTests {
    static func main() async throws {
        precondition(RecipeLinkImporter.validatedURL(" https://example.com/recipe \n") != nil)
        for invalid in ["", "example.com", "https://", "file:///recipe", "javascript:alert(1)", "https://user:secret@example.com"] {
            precondition(RecipeLinkImporter.validatedURL(invalid) == nil, invalid)
        }
        let html = """
        <script type='application/ld+json'>
        {"@graph":[{"@type":"WebPage","name":"Ignore me"},{"@type":["Recipe"],
        "name":"Soup &amp; bread", "description":"<p>Warm &#38; tasty</p>",
        "prepTime":"PT15M", "cookTime":"PT1H5M", "recipeYield":["6 servings"],
        "recipeCategory":"Dinner", "recipeCuisine":"French", "keywords":"Soup, Dinner",
        "recipeIngredient":["2 cups stock", "1 onion"],
        "recipeInstructions":[{"@type":"HowToSection","itemListElement":[
          {"@type":"HowToStep","text":"<p>Chop the onion.</p>"},
          {"@type":"HowToStep","text":"Simmer &amp; serve."}]}]}]}
        </script>
        """
        let recipe = RecipeLinkImporter.parse(html: html).recipe
        precondition(recipe.title == "Soup & bread")
        precondition(recipe.summary == "Warm & tasty")
        precondition(recipe.prepMinutes == 15 && recipe.cookMinutes == 65)
        precondition(recipe.servings == 6)
        precondition(recipe.tags == ["Dinner", "French", "Soup"])
        precondition(recipe.ingredients.map(\.text) == ["2 cups stock", "1 onion"])
        precondition(recipe.steps == ["Chop the onion.", "Simmer & serve."])
        let fallback = RecipeLinkImporter.parse(html: """
        <script type="application/ld+json">broken json</script>
        <meta content="A recipe" property="og:title">
        <meta name="description" content="Easy dinner">
        """).recipe
        precondition(fallback.title == "A recipe" && fallback.summary == "Easy dinner")
        precondition(fallback.ingredients.isEmpty && fallback.steps.isEmpty)
        let alternate = RecipeLinkImporter.parse(html: """
        <script type="application/ld+json">[{"@type":"Recipe","totalTime":"PT45M","prepTime":"PT10M",
        "recipeInstructions":"First.<br>Second.","recipeYield":2}]</script>
        """).recipe
        precondition(alternate.cookMinutes == 35 && alternate.servings == 2)
        precondition(alternate.steps == ["First.", "Second."])
        if CommandLine.arguments.count > 1, let url = URL(string: CommandLine.arguments[1]) {
            let imported = try await RecipeLinkImporter.fetch(url)
            precondition(imported.recipe.recipeLink == url.absoluteString)
            precondition(!imported.recipe.title.isEmpty)
            precondition(!imported.recipe.ingredients.isEmpty)
            precondition(!imported.recipe.steps.isEmpty)
            print("Live import: \(imported.recipe.title), \(imported.recipe.ingredients.count) ingredients, \(imported.recipe.steps.count) steps, photo: \(imported.photo != nil)")
        }
        print("Recipe import tests passed")
    }
}
