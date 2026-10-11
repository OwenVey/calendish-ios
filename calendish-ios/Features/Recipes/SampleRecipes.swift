import Foundation

enum SampleRecipes {
    static let all: [Recipe] = [
        Recipe(title: "Lemon & herb orzo", summary: "A little sunshine in a bowl. Bright lemon, sweet tomatoes, and plenty of fresh herbs.", prepMinutes: 10, cookMinutes: 15, servings: 4, tags: ["Weeknight", "Vegetarian"], symbol: "leaf",
               ingredients: [Ingredient(text: "1½ cups orzo"), Ingredient(text: "2 cups cherry tomatoes"), Ingredient(text: "1 lemon"), Ingredient(text: "¼ cup fresh basil"), Ingredient(text: "2 tbsp olive oil")],
               steps: ["Bring a pot of salted water to a boil. Cook the orzo until tender, then drain.", "Halve the cherry tomatoes and tear the fresh basil. Zest and juice the lemon.", "Toss the warm orzo with olive oil, tomatoes, lemon, and basil. Season to taste and serve."]),
        Recipe(title: "Roasted vegetable bowls", summary: "Colorful roasted vegetables, fluffy rice, and a creamy tahini drizzle.", prepMinutes: 15, cookMinutes: 25, servings: 4, tags: ["Vegetarian"], symbol: "carrot",
               ingredients: [Ingredient(text: "1 cup rice"), Ingredient(text: "2 sweet potatoes"), Ingredient(text: "1 head broccoli"), Ingredient(text: "¼ cup tahini")],
               steps: ["Heat the oven to 425°F. Chop the vegetables and spread on a baking sheet.", "Roast for 25 minutes. Meanwhile, cook the rice.", "Divide rice and vegetables among bowls. Drizzle with tahini and serve."]),
        Recipe(title: "Blueberry overnight oats", summary: "An easy breakfast to wake up to, with juicy blueberries and a spoonful of yogurt.", prepMinutes: 10, cookMinutes: 0, servings: 2, tags: ["Make ahead"], symbol: "sunrise",
               ingredients: [Ingredient(text: "1 cup rolled oats"), Ingredient(text: "1 cup oat milk"), Ingredient(text: "½ cup blueberries")],
               steps: ["Stir oats and oat milk together in two jars.", "Top with blueberries. Cover and refrigerate overnight."], category: .breakfast),
        Recipe(title: "Crispy chickpea salad", summary: "Crunchy chickpeas, crisp greens, and a simple lemon dressing.", prepMinutes: 10, cookMinutes: 20, servings: 2, tags: [], symbol: "fork.knife",
               ingredients: [Ingredient(text: "1 can chickpeas"), Ingredient(text: "4 cups mixed greens"), Ingredient(text: "1 lemon")],
               steps: ["Drain and dry the chickpeas. Roast at 425°F until crisp.", "Toss the greens with lemon dressing and top with the warm chickpeas."], category: .lunch),
    ]
}
