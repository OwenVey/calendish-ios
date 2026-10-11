import Foundation

@main
struct IngredientScalingTests {
    static func main() {
        let cases: [(String, Double, String)] = [
            ("1½ cups orzo", 2, "3 cups orzo"),
            ("1 1/2 cups flour", 0.5, "¾ cups flour"),
            ("1/2 tsp salt", 3, "1½ tsp salt"),
            ("¼ cup tahini", 1.5, "⅜ cup tahini"),
            ("2 tbsp olive oil", 1.0 / 3, "⅔ tbsp olive oil"),
            ("1 lemon", 1.5, "1½ lemon"),
            ("200g butter", 1.5, "300g butter"),
            ("2-3 cloves garlic", 2, "4-6 cloves garlic"),
            ("1 to 2 apples", 3, "3 to 6 apples"),
            ("1.5 kg potatoes", 2, "3 kg potatoes"),
            ("0.75 cup milk", 0.5, "0.38 cup milk"),
            ("1 (15 oz) can chickpeas", 2, "2 (15 oz) can chickpeas"),
            ("Salt to taste", 2, "Salt to taste"),
            ("2 cups stock", 1, "2 cups stock"),
            ("3 eggs", 1.0 / 3, "1 eggs"),
            ("24 cookies", 1.5, "36 cookies"),
            ("1/3 cup water", 1.25, "⅜ cup water"),
            ("1 tsp cumin", 1.06, "1 tsp cumin"),
            ("1 tsp cumin", 0.05, "⅛ tsp cumin"),
            ("1 tsp cumin", 1.95, "2 tsp cumin"),
        ]
        for (input, factor, expected) in cases {
            let actual = Ingredient.scale(input, by: factor)
            precondition(actual == expected, "\(input) × \(factor): expected \(expected), got \(actual)")
        }
        print("Ingredient scaling tests passed")
    }
}
