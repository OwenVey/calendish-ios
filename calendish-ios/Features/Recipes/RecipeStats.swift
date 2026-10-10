import Foundation

/// What the household thinks of a recipe and when it cooked it, for sorting and suggestions.
struct RecipeStats: Hashable {
    var averageRating: Double?
    var ratingCount = 0
    var history = CookedHistory()

    /// Combines ratings with each recipe's cooked history.
    static func make(reviews: [RecipeReview], cooks: [RecipeCook], meals: [PlannedMeal], now: Date = .now) -> [UUID: RecipeStats] {
        var stats = CookedHistory.make(cooks: cooks, meals: meals, now: now).mapValues { RecipeStats(history: $0) }
        for (id, ratings) in Dictionary(grouping: reviews.compactMap { review in review.rating.map { (review.recipeID, $0) } }, by: \.0) {
            stats[id, default: RecipeStats()].averageRating = Double(ratings.map(\.1).reduce(0, +)) / Double(ratings.count)
            stats[id, default: RecipeStats()].ratingCount = ratings.count
        }
        return stats
    }

    /// Recipes worth planning again: rated four stars or more, or a favorite, and not cooked in the last two weeks
    /// or planned from today on. Higher ratings and longer gaps come first.
    static func suggestions(from recipes: [Recipe], stats: [UUID: RecipeStats], meals: [PlannedMeal], now: Date = .now, limit: Int = 5) -> [Recipe] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let planned = Set(meals.filter { calendar.startOfDay(for: $0.date) >= today }.compactMap(\.recipeID))
        let scored = recipes.compactMap { recipe -> (Recipe, Double)? in
            let stat = stats[recipe.id] ?? RecipeStats()
            guard !planned.contains(recipe.id) else { return nil }
            let rating = stat.averageRating ?? (recipe.isFavorite ? 4 : 0)
            guard rating >= 4 || recipe.isFavorite else { return nil }
            let daysSince = stat.history.lastCooked.map { calendar.dateComponents([.day], from: $0, to: today).day ?? 0 }
            if let daysSince, daysSince < 14 { return nil }
            // Up to three extra points for a long gap. Recipes never cooked here count as a month, so a rated
            // recipe the household knows it likes edges out an untried favorite.
            return (recipe, rating + Double(min(daysSince ?? 30, 90)) / 30)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
