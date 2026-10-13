import Foundation
import Supabase

/// The publishable key is safe to ship in the app: Row Level Security decides what each signed-in user can reach.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://wgtrbwbfazdizkevtwfp.supabase.co")!,
    supabaseKey: "sb_publishable_FIRLJ2Axp-wIyRyznxnrSA_qnr3OvO9",
    options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
)

// Record shapes for each table. Views work with the app models in Models.swift instead.

extension Recipe {
    init(_ row: RecipeRecord, favorites: Set<UUID> = []) {
        self.init(id: row.id, title: row.title, summary: row.summary,
                  prepMinutes: row.prepMinutes ?? 0, cookMinutes: row.cookMinutes ?? row.minutes, servings: row.servings,
                  tags: row.tags, symbol: row.symbol, ingredients: row.ingredients, steps: row.steps,
                  isFavorite: favorites.contains(row.id), imagePath: row.imagePath, recipeLink: row.recipeLink,
                  category: row.category.flatMap(RecipeCategory.init(matching:)), yieldText: row.yieldText,
                  owner: row.ownerID.map { .person($0, shared: row.isShared ?? false) } ?? (row.householdID == nil ? nil : .household),
                  revision: row.revision)
    }
    var content: RecipeContentRecord {
        RecipeContentRecord(title: title, summary: summary, minutes: minutes, prepMinutes: prepMinutes, cookMinutes: cookMinutes,
                            servings: servings, tags: tags, symbol: symbol, ingredients: ingredients, steps: steps,
                            imagePath: imagePath, recipeLink: recipeLink, category: category?.rawValue, yieldText: yieldText)
    }
}

extension PlannedMeal {
    init?(_ row: PlannedMealRecord) {
        guard let date = DayFormat.date(from: row.date) else { return nil }
        self.init(id: row.id, date: date, recipe: Recipe(row.recipe), recipeID: row.recipeID, servings: row.servings)
    }
}

extension MealPlanNote {
    init?(_ row: MealPlanNoteRecord) {
        guard let date = DayFormat.date(from: row.date) else { return nil }
        self.init(id: row.id, date: date, text: row.text, items: row.items)
    }
    func record(household: UUID) -> MealPlanNoteRecord {
        MealPlanNoteRecord(id: id, householdID: household, date: DayFormat.string(from: date), text: text, items: items)
    }
}

extension RecipeReview {
    init(_ row: RecipeReviewRecord) {
        self.init(userID: row.userID, recipeID: row.recipeID, rating: row.rating, note: row.note)
    }
    var record: RecipeReviewRecord {
        RecipeReviewRecord(userID: userID, recipeID: recipeID, rating: rating, note: note, updatedAt: .now)
    }
}

extension RecipeCook {
    init?(_ row: RecipeCookRecord) {
        guard let date = DayFormat.date(from: row.cookedOn) else { return nil }
        self.init(recipeID: row.recipeID, date: date, cookedBy: row.cookedBy)
    }
}

extension GroceryItem {
    init(_ row: GroceryItemRecord) {
        self.init(id: row.id, name: row.name, amount: row.amount, source: row.source, isComplete: row.isComplete, position: row.position, aisle: row.aisle)
    }
    func record(household: UUID) -> GroceryItemRecord {
        GroceryItemRecord(id: id, householdID: household, name: name, amount: amount, source: source,
                       isComplete: isComplete, position: position, aisle: aisle)
    }
}
