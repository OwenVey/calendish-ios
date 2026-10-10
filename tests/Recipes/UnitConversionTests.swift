import Foundation

@main
struct UnitConversionTests {
    static func main() {
        let ingredients: [(String, MeasurementPreference, String)] = [
            ("2 cups flour", .metric, "475 ml flour"),
            ("1 lb ground beef", .metric, "455 g ground beef"),
            ("8 oz. cream cheese", .metric, "225 g cream cheese"),
            ("3 lbs potatoes", .metric, "1.35 kg potatoes"),
            ("1-2 cups stock", .metric, "235-475 ml stock"),
            ("1 quart water", .metric, "945 ml water"),
            ("2 tbsp olive oil", .metric, "2 tbsp olive oil"),
            ("200g butter", .us, "7 oz butter"),
            ("500 g pasta", .us, "1 lb pasta"),
            ("250 ml milk", .us, "1 cup milk"),
            ("1 L stock", .us, "4¼ cups stock"),
            ("30 ml lemon juice", .us, "2 tbsp lemon juice"),
            ("5 ml vanilla", .us, "1 tsp vanilla"),
            ("2 cups flour", .us, "2 cups flour"),
            ("2 large eggs", .metric, "2 large eggs"),
            ("2 garlic cloves", .us, "2 garlic cloves"),
            ("1 (15 oz) can chickpeas", .metric, "1 (15 oz) can chickpeas"),
            ("Salt to taste", .metric, "Salt to taste"),
            ("2 cups flour", .original, "2 cups flour"),
        ]
        for (input, units, expected) in ingredients {
            let actual = Ingredient.convert(input, to: units)
            precondition(actual == expected, "\(input) → \(units): expected \(expected), got \(actual)")
        }
        precondition(Ingredient(text: "1½ cups orzo").display(scale: 2, units: .metric) == "710 ml orzo")
        let temperatures: [(String, MeasurementPreference, String)] = [
            ("Heat the oven to 425°F.", .metric, "Heat the oven to 220°C."),
            ("Bake at 350 degrees F for 20 minutes.", .metric, "Bake at 180°C for 20 minutes."),
            ("Roast at 200°C until golden.", .us, "Roast at 400°F until golden."),
            ("Cook to 165°F inside.", .metric, "Cook to 74°C inside."),
            ("Heat the oven to 425°F.", .us, "Heat the oven to 425°F."),
        ]
        for (input, units, expected) in temperatures {
            let actual = Ingredient.convertTemperatures(in: input, to: units)
            precondition(actual == expected, "\(input) → \(units): expected \(expected), got \(actual)")
        }
        print("Unit conversion tests passed")
    }
}
