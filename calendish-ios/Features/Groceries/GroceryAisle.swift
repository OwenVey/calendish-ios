import Foundation

/// Where a grocery item is usually shelved, in the order a shopper typically walks a supermarket.
/// Raw values are stored in the database, so rename titles freely but never change raw values.
nonisolated enum GroceryAisle: String, CaseIterable, Identifiable, Sendable {
    case produce, bakery, meatSeafood = "meat_seafood", deli, dairy, frozen
    case grains, canned, baking, condiments, breakfast, snacks, beverages, alcohol
    case household, personalCare = "personal_care", pets, other
    var id: Self { self }

    var title: String {
        switch self {
        case .produce: "Produce"
        case .bakery: "Bakery"
        case .meatSeafood: "Meat & Seafood"
        case .deli: "Deli"
        case .dairy: "Dairy & Eggs"
        case .frozen: "Frozen"
        case .grains: "Pasta, Rice & Grains"
        case .canned: "Canned & Jarred"
        case .baking: "Baking & Spices"
        case .condiments: "Oils, Sauces & Condiments"
        case .breakfast: "Breakfast & Cereal"
        case .snacks: "Snacks & Sweets"
        case .beverages: "Beverages"
        case .alcohol: "Beer, Wine & Spirits"
        case .household: "Household"
        case .personalCare: "Personal Care"
        case .pets: "Pet Supplies"
        case .other: "Other"
        }
    }

    /// What belongs in the aisle, to steer the on-device model.
    var examples: String {
        switch self {
        case .produce: "fresh fruit, vegetables, and herbs"
        case .bakery: "bread, rolls, tortillas, bagels, and pastries"
        case .meatSeafood: "raw meat, poultry, fish, and shellfish"
        case .deli: "sliced meats, prepared foods, hummus, and specialty cheese"
        case .dairy: "milk, cheese, butter, yogurt, cream, eggs, and plant-based milks"
        case .frozen: "frozen meals, vegetables, fruit, and ice cream"
        case .grains: "pasta, rice, noodles, quinoa, and dried beans"
        case .canned: "canned vegetables, beans, tomatoes, soups, broth, and stock"
        case .baking: "flour, sugar, baking powder, chocolate chips, dried herbs, and spices"
        case .condiments: "cooking oils, vinegar, sauces, dressings, nut butters, and jam"
        case .breakfast: "cereal, oats, granola, pancake mix, and syrup"
        case .snacks: "chips, crackers, nuts, candy, and cookies"
        case .beverages: "water, juice, soda, coffee, and tea"
        case .alcohol: "beer, wine, and spirits, including cooking wine"
        case .household: "cleaning supplies, paper towels, foil, bags, and batteries"
        case .personalCare: "toiletries, medicine, and baby care"
        case .pets: "pet food and supplies"
        case .other: "anything that fits none of the other aisles"
        }
    }

    // MARK: Keywords

    /// Sorts common items by name when the on-device model is unavailable.
    /// Phrases win over single words, and the last word wins over earlier ones,
    /// because it usually names the item: "chicken broth" is broth, not chicken.
    static func guess(for name: String) -> GroceryAisle {
        let words = normalized(name).split(whereSeparator: { !$0.isLetter }).map { singular(String($0)) }
        guard !words.isEmpty else { return .other }
        if words.contains("frozen") { return .frozen }
        if words.contains("canned") { return .canned }
        for length in stride(from: min(3, words.count), through: 2, by: -1) {
            for start in stride(from: words.count - length, through: 0, by: -1) {
                if let aisle = keywords[words[start..<(start + length)].joined(separator: " ")] { return aisle }
            }
        }
        for word in words.reversed() {
            if let aisle = keywords[word] { return aisle }
        }
        return .other
    }

    /// Lowercased with single spaces, so "Milk" and " milk " share a cache entry.
    static func normalized(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        if keywords[word] != nil || word.count <= 3 { return word }
        if word.hasSuffix("ies") { return word.dropLast(3) + "y" }
        if word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    private static let keywords: [String: GroceryAisle] = {
        let lists: [GroceryAisle: String] = [
            .produce: """
                apple, apricot, artichoke, arugula, asparagus, avocado, banana, basil, bean sprout, beet, bell pepper, \
                berry, blackberry, blueberry, bok choy, broccoli, brussels sprout, cabbage, cantaloupe, carrot, cauliflower, \
                celery, chard, cherry, chive, cilantro, clementine, collard, corn, cranberry, cucumber, dill, eggplant, \
                endive, fennel, fig, garlic, ginger, grape, grapefruit, green bean, green onion, herb, honeydew, jalapeno, \
                jalapeño, kale, kiwi, leek, lemon, lemongrass, lettuce, lime, mango, melon, mint, mushroom, nectarine, okra, \
                onion, orange, papaya, parsley, parsnip, pea, peach, pear, pepper, persimmon, pineapple, \
                plantain, plum, pomegranate, potato, pumpkin, radish, raspberry, rhubarb, romaine, rosemary, sage, \
                scallion, shallot, snap pea, spinach, sprout, squash, strawberry, sweet potato, tangerine, thyme, \
                tomatillo, tomato, turnip, watermelon, yam, zucchini, salad, coleslaw mix
                """,
            .bakery: """
                bagel, baguette, bread, brioche, bun, cake, ciabatta, croissant, english muffin, focaccia, muffin, naan, \
                pita, roll, sourdough, tortilla, wrap, pie crust, donut, doughnut, pastry
                """,
            .meatSeafood: """
                bacon, beef, brisket, chicken, chop, chorizo, clam, cod, crab, duck, fish, ground beef, ground turkey, \
                halibut, ham, lamb, lobster, meat, mussel, pork, prawn, ribeye, rib, salmon, sausage, scallop, shrimp, \
                sirloin, steak, tenderloin, thigh, tilapia, trout, tuna steak, turkey, veal, drumstick, wing
                """,
            .deli: """
                deli, hummus, prosciutto, salami, pepperoni, pastrami, roast beef, sliced turkey, rotisserie chicken, \
                brie, feta, goat cheese, burrata, fresh mozzarella, olive bar, guacamole, salsa fresca, pesto
                """,
            .dairy: """
                butter, buttermilk, cheddar, cheese, cottage cheese, cream, cream cheese, creamer, egg, ghee, gruyere, \
                half and half, kefir, margarine, mascarpone, milk, mozzarella, parmesan, parmigiano, pecorino, provolone, \
                ricotta, sour cream, swiss, yogurt, almond milk, oat milk, soy milk, tofu, tempeh, whipped cream, \
                heavy cream, crème fraîche, creme fraiche
                """,
            .frozen: """
                ice cream, gelato, sorbet, popsicle, frozen pizza, waffle fries, tater tot, ice
                """,
            .grains: """
                couscous, farro, fettuccine, lasagna, linguine, macaroni, noodle, orzo, pasta, penne, quinoa, ramen, rice, \
                spaghetti, rigatoni, barley, bulgur, lentil, black bean, chickpea, kidney bean, pinto bean, dried bean, \
                gnocchi, udon, soba, rice noodle
                """,
            .canned: """
                broth, stock, bouillon, canned, chipotle in adobo, coconut milk, diced tomato, tomato paste, tomato sauce, \
                crushed tomato, soup, refried bean, artichoke heart, olive, pickle, sauerkraut, kimchi, roasted red pepper, \
                tuna, sardine, anchovy, evaporated milk, condensed milk
                """,
            .baking: """
                baking powder, baking soda, brown sugar, chocolate chip, cocoa, cornmeal, cornstarch, extract, flour, \
                gelatin, molasses, powdered sugar, sprinkles, sugar, vanilla, yeast, breadcrumb, bread crumb, panko, \
                allspice, bay leaf, black pepper, cardamom, cayenne, chili powder, cinnamon, clove, coriander, cumin, \
                curry powder, garam masala, garlic powder, nutmeg, onion powder, oregano, paprika, peppercorn, \
                red pepper flake, salt, seasoning, sesame seed, spice, turmeric, smoked paprika, italian seasoning
                """,
            .condiments: """
                barbecue sauce, bbq sauce, dressing, fish sauce, honey, hot sauce, jam, jelly, ketchup, mayo, mayonnaise, \
                mustard, oil, olive oil, peanut butter, almond butter, preserve, relish, salsa, soy sauce, sriracha, tahini, \
                teriyaki, vinegar, worcestershire, hoisin, oyster sauce, marinara, pasta sauce, curry paste, miso, gochujang, \
                sesame oil, vegetable oil, canola oil, cooking spray, sauce, nutella, maple syrup
                """,
            .breakfast: """
                cereal, granola, oatmeal, oat, pancake mix, waffle mix, syrup, pop tart, breakfast bar
                """,
            .snacks: """
                almond, candy, cashew, chip, chocolate, cookie, cracker, dried fruit, granola bar, gummy, jerky, nut, \
                peanut, pecan, pistachio, popcorn, pretzel, raisin, trail mix, walnut, pine nut, tortilla chip
                """,
            .beverages: """
                coffee, espresso, juice, kombucha, lemonade, seltzer, soda, sparkling water, tea, water, energy drink, \
                sports drink, cold brew
                """,
            .alcohol: """
                beer, bourbon, champagne, cider, gin, prosecco, rum, sake, tequila, vodka, whiskey, wine, mirin, \
                vermouth, brandy, cooking wine
                """,
            .household: """
                aluminum foil, foil, battery, bleach, detergent, dish soap, dishwasher, garbage bag, light bulb, napkin, \
                paper towel, parchment, plastic wrap, sponge, trash bag, ziploc, zip bag, sandwich bag, cleaner, \
                disinfectant, wipe, candle, freezer bag, cling film
                """,
            .personalCare: """
                conditioner, deodorant, diaper, floss, lotion, mouthwash, razor, shampoo, soap, sunscreen, tissue, \
                toilet paper, toothbrush, toothpaste, vitamin, ibuprofen, tylenol, advil, bandage, cotton swab, \
                body wash, baby wipe, formula
                """,
            .pets: """
                cat food, dog food, cat litter, litter, pet food, dog treat, cat treat, kibble
                """,
        ]
        var keywords: [String: GroceryAisle] = [:]
        for (aisle, list) in lists {
            for keyword in list.split(separator: ",") {
                keywords[keyword.trimmingCharacters(in: .whitespacesAndNewlines)] = aisle
            }
        }
        return keywords
    }()
}
