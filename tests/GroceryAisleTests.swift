import Foundation

@main
struct GroceryAisleTests {
    static func main() {
        let expected: [String: GroceryAisle] = [
            "Milk": .dairy, "eggs": .dairy, "Cherry tomatoes": .produce, "Green beans": .produce, "bananas": .produce,
            "Peanut butter": .condiments, "Chicken broth": .canned, "Chicken thighs": .meatSeafood, "Frozen peas": .frozen,
            "Ice cream": .frozen, "Olive oil": .condiments, "Sourdough bread": .bakery, "Bread crumbs": .baking,
            "Red pepper flakes": .baking, "Bell pepper": .produce, "Black pepper": .baking, "Orzo": .grains,
            "Potato chips": .snacks, "Chocolate chips": .baking, "Paper towels": .household, "Dish soap": .household,
            "Toothpaste": .personalCare, "Dog food": .pets, "Greek yogurt": .dairy, "Cream cheese": .dairy,
            "Coconut milk": .canned, "Rolled oats": .breakfast, "Oat milk": .dairy, "  sparkling   WATER ": .beverages,
            "Dry white wine": .alcohol, "Gochujang": .condiments, "Widget": .other, "": .other,
        ]
        for (name, aisle) in expected {
            let guess = GroceryAisle.guess(for: name)
            precondition(guess == aisle, "\(name) should be \(aisle.title), not \(guess.title)")
        }
        precondition(GroceryAisle.normalized(" Sparkling  Water") == "sparkling water", "Names must share a cache entry regardless of case or spacing")
        print("Grocery aisle tests passed")
    }
}
