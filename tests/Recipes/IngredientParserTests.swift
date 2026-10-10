import Foundation

@main
struct IngredientParserTests {
    static func main() {
        let amounts: [(String, String?)] = [
            ("1 cup unsalted butter, softened", "1 cup"),
            ("2 large eggs", "2"),
            ("½ tsp salt", "½ tsp"),
            ("1½ cups orzo", "1½ cups"),
            ("1-2 cups stock", "1-2 cups"),
            ("2 to 3 tbsp. olive oil", "2 to 3 tbsp."),
            ("200g butter", "200g"),
            ("1 (15 oz) can chickpeas", "1"),
            ("1 lemon", "1"),
            ("1 head broccoli", "1 head"),
            ("Salt to taste", nil),
            ("2x flour", nil),
        ]
        for (line, expected) in amounts {
            let actual = IngredientParser.amountRange(in: line).map { String(line[$0]) }
            precondition(actual == expected, "amount of \(line): expected \(expected ?? "nil"), got \(actual ?? "nil")")
        }

        let names: [(String, String)] = [
            ("1 cup unsalted butter, softened", "unsalted butter"),
            ("1 cup packed brown sugar", "packed brown sugar"),
            ("2 large eggs", "large eggs"),
            ("1 (15 oz) can chickpeas", "chickpeas"),
            ("2 cups of flour", "flour"),
            ("Pinch of salt", "salt"),
            ("Salt to taste", "Salt"),
            ("1 head broccoli", "broccoli"),
            ("Parsley, for garnish", "Parsley"),
            ("2 tbsp olive oil plus more for drizzling", "olive oil"),
            ("1 lb boneless, skinless chicken breasts, cubed", "skinless chicken breasts"),
            ("6 bone-in chicken thighs", "bone-in chicken thighs"),
        ]
        for (line, expected) in names {
            let actual = IngredientParser.name(of: line)
            precondition(actual == expected, "name of \(line): expected \(expected), got \(actual)")
        }

        let cookies = ["1 cup unsalted butter, softened", "1 cup granulated sugar", "1 cup packed brown sugar", "2 large eggs",
                       "1 tsp vanilla extract", "3 cups all-purpose flour", "1 tsp baking soda", "½ tsp salt", "2 cups chocolate chips",
                       "2 garlic cloves", "1 cup cherry tomatoes", "1 tsp garlic powder"]
        let steps: [(String, [(String, [Int])])] = [
            ("In a large mixing bowl, cream together the softened butter, granulated sugar, and brown sugar until light and fluffy.",
             [("butter", [0]), ("granulated sugar", [1]), ("brown sugar", [2])]),
            ("Add the eggs one at a time. Stir in the vanilla extract.", [("eggs", [3]), ("vanilla extract", [4])]),
            ("Whisk the flour, baking soda, and salt. Add the sugar.", [("flour", [5]), ("baking soda", [6]), ("salt", [7]), ("sugar", [1, 2])]),
            ("Crack an egg, mince the garlic, halve each tomato, and fold in the chips.",
             [("egg", [3]), ("garlic", [9]), ("tomato", [10]), ("chips", [8])]),
            ("Season with the powder and some saltines.", []),
            ("Rub the chicken with oil, salt, and pepper.", [("salt", [7])]),
        ]
        for (step, expected) in steps {
            let actual = IngredientParser.mentions(in: step, ingredients: cookies).map { (String(step[$0.range]), $0.ingredients.sorted()) }
            precondition(actual.map(\.0) == expected.map(\.0) && actual.map(\.1) == expected.map(\.1),
                         "mentions in \(step): expected \(expected), got \(actual)")
        }
        let chicken = ["6 bone-in chicken thighs", "1 lb boneless, skinless chicken breasts", "3 tbsp olive oil", "Salt and pepper", "2 ears corn"]
        let chickenSteps: [(String, [(String, [Int])])] = [
            ("Rub the chicken thighs with the remaining oil, salt, and pepper.", [("chicken thighs", [0]), ("oil", [2]), ("salt", [3]), ("pepper", [3])]),
            ("Nestle the chicken skin side up, then add the corn.", [("chicken", [0, 1]), ("corn", [4])]),
            ("Slice the breasts. Salt and pepper to taste.", [("breasts", [1]), ("Salt and pepper", [3])]),
            ("Keep the bone-in pieces skin side up.", []),
        ]
        for (step, expected) in chickenSteps {
            let actual = IngredientParser.mentions(in: step, ingredients: chicken).map { (String(step[$0.range]), $0.ingredients.sorted()) }
            precondition(actual.map(\.0) == expected.map(\.0) && actual.map(\.1) == expected.map(\.1),
                         "mentions in \(step): expected \(expected), got \(actual)")
        }
        let keys: [(String, String)] = [
            ("1 large onion, diced", "onion"),
            ("2 onions", "onion"),
            ("1 cup unsalted butter, softened", "unsalted butter"),
            ("2 tbsp salted butter", "salted butter"),
            ("3 ripe tomatoes", "tomato"),
            ("1 cup fresh blueberries", "fresh blueberry"),
            ("Salt to taste", "salt"),
            ("1 cup", ""),
        ]
        for (line, expected) in keys {
            let actual = IngredientParser.foodKey(of: line)
            precondition(actual == expected, "food key of \(line): expected \(expected), got \(actual)")
        }
        precondition(IngredientParser.plural(of: "onion") == "onions" && IngredientParser.plural(of: "berry") == "berries")

        print("Ingredient parser tests passed")
    }
}
