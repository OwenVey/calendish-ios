import Foundation

@main
struct RecipeLinkImporterTests {
    static func main() async throws {
        precondition(RecipeLinkImporter.validatedURL(" https://example.com/recipe \n") != nil)
        for invalid in ["", "example.com", "https://", "file:///recipe", "javascript:alert(1)", "https://user:secret@example.com"] {
            precondition(RecipeLinkImporter.validatedURL(invalid) == nil, invalid)
        }

        // The same page shared twice is recognized; different pages aren't.
        let sameSources = [
            ("https://www.example.com/soup/?utm_source=pinterest#recipe", "http://example.com/soup"),
            ("https://youtu.be/abc123?si=xyz", "https://www.youtube.com/watch?v=abc123&feature=shared"),
            ("https://youtube.com/shorts/abc123", "https://m.youtube.com/watch?v=abc123"),
            ("https://www.instagram.com/reel/C1x2y3/?igsh=abc", "https://instagram.com/p/C1x2y3"),
            ("https://www.facebook.com/reel/972153655943201?mibextid=abc", "https://m.facebook.com/61552152101386/videos/apple-fritter-loaf-cake/972153655943201/"),
            ("https://www.facebook.com/watch/?v=972153655943201", "https://facebook.com/cook/videos/972153655943201"),
            ("https://example.com/r?b=2&a=1", "https://example.com/r?a=1&b=2"),
        ]
        for (first, second) in sameSources {
            precondition(RecipeSourceLink.key(first) == RecipeSourceLink.key(second), "\(first) ≠ \(second)")
        }
        for (first, second) in [("https://example.com/soup", "https://example.com/stew"), ("https://example.com/r?id=1", "https://example.com/r?id=2"),
                                ("https://youtu.be/abc", "https://youtu.be/abd"),
                                ("https://www.facebook.com/reel/123", "https://www.facebook.com/reel/124"), ("https://example.com/soup", "https://example.org/soup")] {
            precondition(RecipeSourceLink.key(first) != RecipeSourceLink.key(second), "\(first) = \(second)")
        }
        var saved = SampleRecipes.all[0], other = SampleRecipes.all[1]
        saved.recipeLink = "https://www.example.com/soup/"
        other.recipeLink = "https://example.com/stew"
        precondition(RecipeSourceLink.recipe(from: URL(string: "https://example.com/soup?fbclid=1")!, in: [other, saved])?.id == saved.id)
        precondition(RecipeSourceLink.recipe(from: URL(string: "https://example.com/stew")!, in: [saved]) == nil)
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
        precondition(recipe.category == .dinner && recipe.tags == ["French", "Soup"])
        precondition(recipe.ingredients.map(\.text) == ["2 cups stock", "1 onion"])
        precondition(recipe.steps == ["Chop the onion.", "Simmer & serve."])
        for (categories, expected) in [("\"Main Course\"", nil), ("[\"Cakes\",\"desserts\"]", RecipeCategory.dessert)] {
            let categorized = RecipeLinkImporter.parse(html: """
            <script type="application/ld+json">{"@type":"Recipe","recipeCategory":\(categories)}</script>
            """).recipe
            precondition(categorized.category == expected, categories)
        }
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
