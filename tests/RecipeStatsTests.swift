import Foundation

@main
struct RecipeStatsTests {
    static func check(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); exit(1) }
    }

    static func main() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 18))!
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))! }
        var recipes = SampleRecipes.all
        let me = UUID(), partner = UUID()
        recipes[3].isFavorite = true
        let (orzo, bowls, oats, salad) = (recipes[0], recipes[1], recipes[2], recipes[3])

        let reviews = [
            RecipeReview(userID: me, recipeID: orzo.id, rating: 5, note: "Use half the salt."),
            RecipeReview(userID: partner, recipeID: orzo.id, rating: 4),
            RecipeReview(userID: me, recipeID: bowls.id, rating: 5),
            RecipeReview(userID: me, recipeID: oats.id, rating: nil, note: "Add cinnamon."),
        ]
        let cooks = [
            RecipeCook(recipeID: orzo.id, date: daysAgo(21)),
            RecipeCook(recipeID: bowls.id, date: daysAgo(3)),
        ]
        let meals = [
            // A past planned meal counts as cooked, on the same day as a marked cook only once.
            PlannedMeal(date: daysAgo(21), recipe: orzo, recipeID: orzo.id, servings: 4),
            PlannedMeal(date: daysAgo(40), recipe: orzo, recipeID: orzo.id, servings: 4),
            // Today's and future meals haven't been cooked yet.
            PlannedMeal(date: daysAgo(0), recipe: oats, recipeID: oats.id, servings: 2),
        ]
        let stats = RecipeStats.make(reviews: reviews, cooks: cooks, meals: meals, now: now)

        check(stats[orzo.id]?.averageRating == 4.5, "average rating")
        check(stats[orzo.id]?.ratingCount == 2, "rating count")
        check(stats[orzo.id]?.cookedDays == [daysAgo(21), daysAgo(40)], "cooked days merge and sort")
        check(stats[oats.id]?.averageRating == nil && stats[oats.id]?.lastCooked == nil, "note-only review and today's meal")
        check(stats[bowls.id]?.lastCooked == daysAgo(3), "marked cook")

        check(RecipeSort.rating.sorted(recipes, stats: stats).map(\.id) == [bowls.id, orzo.id, oats.id, salad.id], "highest rated")
        check(RecipeSort.recentlyCooked.sorted(recipes, stats: stats).map(\.id) == [bowls.id, orzo.id, oats.id, salad.id], "recently cooked")
        check(RecipeSort.leastRecentlyCooked.sorted(recipes, stats: stats).map(\.id) == [oats.id, salad.id, orzo.id, bowls.id], "least recently cooked")

        // Bowls were cooked three days ago and oats are planned today, so neither is suggested.
        let suggested = RecipeStats.suggestions(from: recipes, stats: stats, meals: meals, now: now)
        check(suggested.map(\.id) == [orzo.id, salad.id], "suggestions: \(suggested.map(\.title))")

        check(RecipeStats.cookedAgo(daysAgo(0), now: now) == "today", "today: \(RecipeStats.cookedAgo(daysAgo(0), now: now))")
        check(RecipeStats.cookedAgo(daysAgo(1), now: now) == "yesterday", "yesterday")
        check(RecipeStats.cookedAgo(daysAgo(21), now: now) == "3 weeks ago", "weeks: \(RecipeStats.cookedAgo(daysAgo(21), now: now))")
        check(RecipeStats.cookedAgo(daysAgo(65), now: now) == "2 months ago", "months")
        print("Recipe stats tests passed")
    }
}
