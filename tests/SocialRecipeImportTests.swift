import Foundation

/// Social links go through the same link importer as recipe sites, with recorded pages in place of the network.
@main
struct SocialRecipeImportTests {
    static func main() async throws {
        try await youTubeDescriptionWithOnlyIngredients()
        try await instagramShareLinkCaption()
        try await tikTokShortLinkCaption()
        try await tikTokCaptionFromEmbedWhenPageHasNone()
        try await linkedRecipePageWinsOverConflictingDescription()
        try await captionWhenLinkedPageIsUnavailableOrNotARecipe()
        try await metadataOnlyPostFails()
        try await privateOrDeletedPostFails()
        try await sharedTextWhenPostIsUnreadable()
        sharesKeepTextSharedWithALink()
        try await instructionsOnlyCaption()
        try await firstOfSeveralRecipes()
        try await oneRecipeWithIngredientsForEachPart()
        try await captionEdgeCases()
        try await cancellingStopsTheImport()
        try await recipeSitesStillUseTheirMetadata()
        if RecipeTextImporter.modelIsAvailable {
            try await modelKeepsToWhatTheCaptionSays()
            print("On-device model checks passed")
        } else {
            print("On-device model unavailable: skipped model checks")
        }
        print("Social recipe import tests passed")
    }

    static func youTubeDescriptionWithOnlyIngredients() async throws {
        let link = URL(string: "https://youtu.be/BJVFg2AXCtw")!
        let pages = Pages([
            "https://youtu.be/BJVFg2AXCtw": .page(at: "https://m.youtube.com/watch?v=BJVFg2AXCtw", youTubePage(
                title: "Most requested PASTA recipe ✨❤️",
                description: "Ingredients: \nFor 2 servings \n----------------------------------------\nPasta - 2 Cups \nPasta sauce - 1/2 a jar \nGarlic - 4 cloves \nMushrooms - 200 g \nOnion - 1 small \nSpinach - a handful \nSausage - 4 to 5 \nOregano \nChilli flakes \nSalt \nCream cheese - 1 1/2 tbsp")),
        ])
        let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
        expect(recipe.title, "Most requested PASTA recipe ✨❤️")
        expect(recipe.ingredients.map(\.text), ["Pasta - 2 Cups", "Pasta sauce - 1/2 a jar", "Garlic - 4 cloves", "Mushrooms - 200 g",
                                                "Onion - 1 small", "Spinach - a handful", "Sausage - 4 to 5", "Oregano", "Chilli flakes",
                                                "Salt", "Cream cheese - 1 1/2 tbsp"])
        expect(recipe.steps, [])
        expect(recipe.servings, 2)
        expect(recipe.prepMinutes, 0)
        expect(recipe.cookMinutes, 0)
        expect(recipe.recipeLink, link.absoluteString)
    }

    static func instagramShareLinkCaption() async throws {
        let link = URL(string: "https://www.instagram.com/share/reel/BAJcXhq0b1")!
        let pages = Pages([
            link.absoluteString: .page(at: "https://www.instagram.com/reel/DePh8DLupVq/", "<html><meta property=\"og:description\" content=\"11K likes - recipeincaption: &quot;Crispy Cheesy&quot;\"></html>"),
            "https://www.instagram.com/p/DePh8DLupVq/embed/captioned/": .page(instagramEmbed(user: "recipeincaption", caption: hashbrowns)),
        ])
        let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
        expect(recipe.title, "Crispy Cheesy Hashbrowns 🥔")
        expect(recipe.ingredients.map(\.text), ["5 large russet potatoes", "3 tbsps corn starch",
                                                "Seasonings: 1 tsp each of garlic powder, onion powder, paprika, salt and pepper",
                                                "1/2 cup white cheddar, freshly grated", "1/4 cup parmesan, optional", "Neutral oil, for frying",
                                                "1/2 cup mayonnaise", "1/4 cup ketchup", "1 to 2 tbsp sriracha (or different hot sauce)",
                                                "1 tsp pickle juice, optional"])
        expect(recipe.steps.count, 7)
        expect(recipe.steps.first, "Wash & peel potatoes. Add to a pot of cold water with 2 tbsp salt. Bring to a boil and cook 10–12 mins until tender outside but still firm in the center. Don’t fully cook them!")
        expect(recipe.steps.last, "Serve hot with your favorite dipping sauce… I choose to simply mix mayo, ketchup & sriracha until smooth.")
        expect(recipe.servings, PreferenceKey.servingsForNewRecipes)
        expect(recipe.recipeLink, link.absoluteString)
    }

    static func tikTokShortLinkCaption() async throws {
        let link = URL(string: "https://vm.tiktok.com/ZMabc123/")!
        let pages = Pages([
            link.absoluteString: .page(at: "https://www.tiktok.com/@cook/video/7123?_r=1", tikTokPage(id: "7123", caption: noodles)),
        ])
        let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
        expectNoodles(recipe)
        expect(recipe.recipeLink, link.absoluteString)
    }

    static func tikTokCaptionFromEmbedWhenPageHasNone() async throws {
        let link = URL(string: "https://www.tiktok.com/@cook/video/7123")!
        let oEmbed = String(data: try JSONSerialization.data(withJSONObject: ["title": noodles, "author_name": "Cook"]), encoding: .utf8)!
        let pages = Pages([
            link.absoluteString: .page("<html><title>TikTok - Make Your Day</title></html>"),
            "https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40cook%2Fvideo%2F7123": .page(oEmbed),
        ])
        expectNoodles(try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe)
    }

    static func expectNoodles(_ recipe: Recipe) {
        expect(recipe.title, "Garlic butter noodles 🍜")
        expect(recipe.ingredients.map(\.text), ["200g noodles", "3 tbsp butter", "4 cloves garlic"])
        expect(recipe.steps, ["Boil the noodles.", "Melt the butter with the garlic.", "Toss and serve."])
    }

    static func linkedRecipePageWinsOverConflictingDescription() async throws {
        let link = URL(string: "https://www.youtube.com/watch?v=soup1")!
        let description = """
            Ingredients:
            1 onion
            3 cups stock

            Full recipe: https://cook.example/tomato-soup
            Shop my pans: https://www.amazon.com/shop/cook
            """
        let pages = Pages([
            link.absoluteString: .page(youTubePage(title: "Tomato soup in 10 minutes", description: description)),
            "https://cook.example/tomato-soup": .page(recipePage),
        ])
        let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
        expect(recipe.title, "Tomato Soup")
        expect(recipe.ingredients.map(\.text), ["2 onions", "4 cups stock", "800 g tomatoes"])
        expect(recipe.steps, ["Soften the onions.", "Simmer with the stock and tomatoes for 20 minutes."])
        expect(recipe.servings, 6)
        expect(recipe.recipeLink, link.absoluteString)
        precondition(!pages.requested.contains { $0.contains("amazon") }, "Shopping links aren't recipe pages")
    }

    static func captionWhenLinkedPageIsUnavailableOrNotARecipe() async throws {
        let description = "Ingredients:\n1 onion\n3 cups stock\n\nRecipe: https://cook.example/tomato-soup"
        for linkedPage in [Pages.Response.status(404), .page("<html><title>Cook's shop</title><body>Pans and knives</body></html>")] {
            let link = URL(string: "https://www.youtube.com/watch?v=soup2")!
            let pages = Pages([
                link.absoluteString: .page(youTubePage(title: "Quick soup", description: description)),
                "https://cook.example/tomato-soup": linkedPage,
            ])
            let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
            expect(recipe.title, "Quick soup")
            expect(recipe.ingredients.map(\.text), ["1 onion", "3 cups stock"])
            expect(recipe.steps, [])
            expect(recipe.recipeLink, link.absoluteString)
        }
    }

    static func metadataOnlyPostFails() async throws {
        let link = URL(string: "https://www.tiktok.com/@cook/video/7124")!
        let pages = Pages([
            link.absoluteString: .page(tikTokPage(id: "7124", caption: "Best pasta of my life 🍝🔥 #pasta #foodtok #dinner")),
        ])
        try await expectNoRecipe(link, pages)
    }

    static func privateOrDeletedPostFails() async throws {
        let link = URL(string: "https://www.instagram.com/p/Private1/")!
        // The post page's preview has the start of the caption, but a preview isn't the whole recipe.
        let pages = Pages([
            link.absoluteString: .page("<meta property=\"og:description\" content=\"Ingredients: 2 eggs, 1 cup flour…\">"),
            "https://www.instagram.com/p/Private1/embed/captioned/": .status(404),
        ])
        try await expectNoRecipe(link, pages)
    }

    static func sharedTextWhenPostIsUnreadable() async throws {
        let link = URL(string: "https://www.instagram.com/reel/Private2/")!
        let pages = Pages(["https://www.instagram.com/p/Private2/embed/captioned/": .status(404)])
        let recipe = try await RecipeLinkImporter.fetch(link, sharedText: noodles, loader: pages.loader, usesModel: false).recipe
        expectNoodles(recipe)
        expect(recipe.recipeLink, link.absoluteString)
    }

    static func sharesKeepTextSharedWithALink() {
        let link = URL(string: "https://www.instagram.com/reel/Private2/")!
        guard case .link(let url, let text) = RecipeImport.combined([.text(noodles), .from(text: link.absoluteString)]) else {
            preconditionFailure("A link and its caption are imported as the link")
        }
        expect(url, link)
        expect(text, noodles)
        guard case .link(_, nil) = RecipeImport.combined([.from(text: link.absoluteString)]) else { preconditionFailure("No text was shared") }
        guard case .pdf = RecipeImport.combined([.text(noodles), .link(link), .pdf(Data())]) else { preconditionFailure("PDFs come first") }
    }

    static func instructionsOnlyCaption() async throws {
        let link = URL(string: "https://www.instagram.com/p/Lemon1/")!
        let pages = Pages([
            "https://www.instagram.com/p/Lemon1/embed/captioned/": .page(instagramEmbed(user: "cook", caption: """
                Lemon butter pasta 🍋

                Method:
                1. Boil the pasta in salted water.
                2. Toss it with lemon zest and butter.

                Follow for more easy dinners!
                """)),
        ])
        let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
        expect(recipe.title, "Lemon butter pasta 🍋")
        expect(recipe.ingredients.map(\.text), [])
        expect(recipe.steps, ["Boil the pasta in salted water.", "Toss it with lemon zest and butter."])
        expect(recipe.servings, PreferenceKey.servingsForNewRecipes)
        expect(recipe.prepMinutes + recipe.cookMinutes, 0)
    }

    static func firstOfSeveralRecipes() async throws {
        let link = URL(string: "https://www.tiktok.com/@cook/video/7125")!
        let pages = Pages([
            link.absoluteString: .page(tikTokPage(id: "7125", caption: """
                Recipe 1: Garlic Noodles
                Ingredients:
                200g noodles
                4 cloves garlic
                Steps:
                1. Boil the noodles.
                2. Toss with the garlic.

                Recipe 2: Green Salad
                Ingredients:
                1 lettuce
                2 tbsp dressing
                Steps:
                1. Toss together.
                """)),
        ])
        let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
        expect(recipe.title, "Garlic Noodles")
        expect(recipe.ingredients.map(\.text), ["200g noodles", "4 cloves garlic"])
        expect(recipe.steps, ["Boil the noodles.", "Toss with the garlic."])
    }

    static func oneRecipeWithIngredientsForEachPart() async throws {
        let recipe = try await captionRecipe("""
            Cheese pie
            Dough
            Ingredients:
            2 cups flour

            Filling
            Ingredients:
            1 cup cheese
            Instructions:
            1. Make the dough.
            2. Fill and bake.
            """)
        expect(recipe.title, "Cheese pie")
        expect(recipe.ingredients.map(\.text), ["2 cups flour", "1 cup cheese"])
        expect(recipe.steps, ["Make the dough.", "Fill and bake."])
    }

    static func captionEdgeCases() async throws {
        // A part's heading inside the method isn't the ingredients.
        let sauce = try await captionRecipe("Teriyaki\nInstructions\nFor the sauce:\nWhisk the soy sauce and sugar.\nGlaze the chicken.")
        expect(sauce.ingredients.map(\.text), [])
        expect(sauce.steps, ["For the sauce:", "Whisk the soy sauce and sugar.", "Glaze the chicken."])
        // Numbered recipes aren't hashtags.
        let numbered = try await captionRecipe("Recipe #1: Garlic Noodles\nIngredients:\n200g noodles\n\nRecipe #2: Salad\nIngredients:\n1 lettuce")
        expect(numbered.title, "Garlic Noodles")
        // A time's value can be on the next line, after a blank one.
        let timed = try await captionRecipe("Soup\nPrep Time\n\n15 minutes\nIngredients:\n1 onion")
        expect(timed.prepMinutes, 15)
    }

    static func captionRecipe(_ caption: String) async throws -> Recipe {
        let link = URL(string: "https://www.tiktok.com/@cook/video/7200")!
        let pages = Pages([link.absoluteString: .page(tikTokPage(id: "7200", caption: caption))])
        return try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
    }

    static func cancellingStopsTheImport() async throws {
        let link = URL(string: "https://www.tiktok.com/@cook/video/7126")!
        // The network reports a cancelled request as a URL error.
        let loader = PageLoader { _ in
            try await Task.sleep(for: .seconds(5))
            throw URLError(.cancelled)
        }
        let task = Task { try await RecipeLinkImporter.fetch(link, loader: loader, usesModel: false) }
        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("A cancelled import has no recipe")
        } catch {
            precondition(error is CancellationError, "Expected cancellation, got \(error.localizedDescription)")
        }
    }

    static func recipeSitesStillUseTheirMetadata() async throws {
        let link = URL(string: "https://cook.example/tomato-soup")!
        let pages = Pages([
            link.absoluteString: .page(recipePage.replacingOccurrences(of: "<title>", with: "<meta property=\"og:image\" content=\"/soup.jpg\"><title>")),
            "https://cook.example/soup.jpg": .page("photo"),
        ])
        let imported = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false)
        expect(imported.recipe.title, "Tomato Soup")
        expect(imported.recipe.ingredients.map(\.text), ["2 onions", "4 cups stock", "800 g tomatoes"])
        expect(imported.recipe.recipeLink, link.absoluteString)
        expect(imported.photo, Data("photo".utf8))
    }

    /// Wording can change between model versions, so these check that nothing is added to what the caption says.
    static func modelKeepsToWhatTheCaptionSays() async throws {
        // Recorded from tiktok.com/@alya.cookss/video/7666457673751072033 on 2026-10-09: ingredients without quantities or a method.
        let caption = "Creamy Beef Tomato Pasta🍝 An easy, quick and absolutely delicious beef pasta🤤 All you need is:  •pasta🍝 •beef mince🥩 •onion🧅 •garlic🧄 •tomato sauce🍅 •cream🥛 •parsley(*optional)🌱 •spices(salt, black pepper, smoked paprika, garlic powder)🧂 #pasta #beefpasta #tomatopasta #easypasta #easyrecipes "
        let link = URL(string: "https://www.tiktok.com/@alya.cookss/video/7666457673751072033")!
        let pages = Pages([link.absoluteString: .page(tikTokPage(id: "7666457673751072033", caption: caption))])
        if let recipe = try? await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: true).recipe {
            precondition(!recipe.ingredients.isEmpty, "A recipe needs what the caption lists")
            precondition(!recipe.ingredients.contains { $0.text.contains(where: \.isNumber) }, "Invented quantities: \(recipe.ingredients.map(\.text))")
            expect(recipe.steps, [])
            expect(recipe.servings, PreferenceKey.servingsForNewRecipes)
            expect(recipe.prepMinutes + recipe.cookMinutes, 0)
        }

        let metadata = Pages([link.absoluteString: .page(tikTokPage(id: "7666457673751072033", caption: "Best pasta of my life 🍝🔥 #pasta #foodtok"))])
        do {
            let recipe = try await RecipeLinkImporter.fetch(link, loader: metadata.loader, usesModel: true).recipe
            preconditionFailure("Expected no recipe, got \(recipe.ingredients.map(\.text)) \(recipe.steps)")
        } catch {
            expect(error.localizedDescription, "Couldn’t get a recipe from this link.")
        }

        // Lists under headings are copied exactly, whatever the model writes.
        let post = URL(string: "https://www.instagram.com/p/DePh8DLupVq/")!
        let captioned = Pages(["https://www.instagram.com/p/DePh8DLupVq/embed/captioned/": .page(instagramEmbed(user: "recipeincaption", caption: hashbrowns))])
        let withModel = try await RecipeLinkImporter.fetch(post, loader: captioned.loader, usesModel: true).recipe
        let withoutModel = try await RecipeLinkImporter.fetch(post, loader: captioned.loader, usesModel: false).recipe
        expect(withModel.ingredients.map(\.text), withoutModel.ingredients.map(\.text))
        expect(withModel.steps, withoutModel.steps)
        precondition(withModel.title.localizedCaseInsensitiveContains("hashbrown"), withModel.title)
    }

    static func expectNoRecipe(_ link: URL, _ pages: Pages, file: StaticString = #file, line: UInt = #line) async throws {
        do {
            let recipe = try await RecipeLinkImporter.fetch(link, loader: pages.loader, usesModel: false).recipe
            preconditionFailure("Expected no recipe, got \(recipe.title): \(recipe.ingredients.map(\.text)) \(recipe.steps)", file: file, line: line)
        } catch {
            expect(error.localizedDescription, "Couldn’t get a recipe from this link.", file: file, line: line)
        }
    }

    // MARK: Recorded pages

    static let recipePage = """
        <html><head><title>Tomato Soup | Cook</title><script type="application/ld+json">{"@type":"Recipe","name":"Tomato Soup",
        "recipeYield":"6","recipeIngredient":["2 onions","4 cups stock","800 g tomatoes"],
        "recipeInstructions":[{"@type":"HowToStep","text":"Soften the onions."},{"@type":"HowToStep","text":"Simmer with the stock and tomatoes for 20 minutes."}]}</script>
        </head><body>…</body></html>
        """

    static let noodles = "Garlic butter noodles 🍜\nIngredients:\n200g noodles\n3 tbsp butter\n4 cloves garlic\nSteps:\n1. Boil the noodles.\n2. Melt the butter with the garlic.\n3. Toss and serve.\n#noodles #fyp"

    /// The shape of a TikTok video page: the caption is the `desc` of the video's item in its hydration data.
    static func tikTokPage(id: String, caption: String) -> String {
        let data: [String: Any] = ["__DEFAULT_SCOPE__": ["webapp.reflow.video.detail": ["itemInfo": ["itemStruct": [
            "id": id, "desc": caption, "music": ["id": "1", "desc": "original sound"]]]]]]
        let json = String(data: try! JSONSerialization.data(withJSONObject: data), encoding: .utf8)!
        return """
        <html><head><meta property="og:description" content="1K likes. \(caption.prefix(30))"></head><body>
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">\(json)</script></body></html>
        """
    }

    /// A public post's caption, as recorded from instagram.com/p/DePh8DLupVq on 2026-10-09.
    static let hashbrowns = """
        Crispy Cheesy Hashbrowns 🥔

        Comment “Recipe” and I’ll send you the full recipe card with more details for free!!

        I tested over 100 potato recipes and have finally cracked the code to the crispiest, golden-est and tastiest hashbrowns of all time… 🔥

        For the Hashbrowns:
        -5 large russet potatoes
        -3 tbsps corn starch
        -Seasonings: 1 tsp each of garlic powder, onion powder, paprika, salt and pepper
        -1/2 cup white cheddar, freshly grated
        -1/4 cup parmesan, optional
        -Neutral oil, for frying

        For the Dipping Sauce:
        -1/2 cup mayonnaise
        -1/4 cup ketchup
        -1 to 2 tbsp sriracha (or different hot sauce)
        -1 tsp pickle juice, optional

        Instructions:

        1. Wash & peel potatoes. Add to a pot of cold water with 2 tbsp salt. Bring to a boil and cook 10–12 mins until tender outside but still firm in the center. Don’t fully cook them!
        2. Drain & cool. Coarsely grate using the large holes of a box grater, then gently squeeze out excess moisture with a clean towel or paper towels. Water is your enemy here!! 🙅‍♂️
        3. Combine grated potatoes with cornstarch, seasonings, & the cheese. Mix until evenly combined.
        4. Using your hands, firmly shape into thick oval patties, pressing tightly so they hold together.
        5. Key step: Place on a parchment-lined sheet pan or plate & freeze for at least 45 mins, or until firm. This helps prevent them from falling apart while frying!
        6. Heat neutral oil to 350°F (175°C) in a deep skillet or pot. Fry in batches for 3–4 mins per side until golden & crispy. Adjust heat as needed to maintain 350°F because the oil temperature drops when adding potatoes.
        7. Serve hot with your favorite dipping sauce… I choose to simply mix mayo, ketchup & sriracha until smooth.

        #hashbrowns #potato #easyrecipes
        """

    /// The shape of Instagram's captioned embed page: the caption follows the creator's name, with line breaks as `<br />`.
    static func instagramEmbed(user: String, caption: String) -> String {
        let html = caption.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\n", with: "<br />")
        return """
        <html><body><div class="Caption"><a class="CaptionUsername" href="https://www.instagram.com/\(user)/" target="_blank">\(user)</a><br /><br />\(html)<div class="CaptionComments"><a href="#">View all comments</a></div></div></body></html>
        """
    }

    static func youTubePage(title: String, description: String) -> String {
        let json = String(data: try! JSONSerialization.data(withJSONObject: description, options: .fragmentsAllowed), encoding: .utf8)!
        return """
        <html><head><meta property="og:title" content="\(title)"><meta property="og:description" content="\(description.prefix(80))">
        </head><body><script>var ytInitialPlayerResponse = {"videoDetails":{"videoId":"x","title":"\(title)","shortDescription":\(json),"isLive":false}};</script></body></html>
        """
    }

    static func expect<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
        precondition(actual == expected, "\nExpected: \(expected)\nActual:   \(actual)", file: file, line: line)
    }
}

/// Responses keyed by the requested address. Anything else fails the way an unreachable page does.
final class Pages: @unchecked Sendable {
    enum Response {
        case page(at: String, String)
        case status(Int)
        static func page(_ body: String) -> Response { .page(at: "", body) }
    }

    private let responses: [String: Response]
    private(set) var requested: [String] = []

    init(_ responses: [String: Response]) { self.responses = responses }

    var loader: PageLoader {
        PageLoader { url in
            self.requested.append(url.absoluteString)
            switch self.responses[url.absoluteString] {
            case .page(let finalURL, let body):
                return LoadedPage(url: URL(string: finalURL.isEmpty ? url.absoluteString : finalURL)!, status: 200, data: Data(body.utf8))
            case .status(let status):
                return LoadedPage(url: url, status: status, data: Data())
            case nil:
                throw URLError(.cannotFindHost)
            }
        }
    }
}
