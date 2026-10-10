import Foundation

struct HouseholdSnapshot {
    var household: Household?
    var members: [HouseholdMember] = []
    var recipes: [Recipe] = []
    var meals: [PlannedMeal] = []
    var notes: [MealPlanNote] = []
    var reviews: [RecipeReview] = []
    var cooks: [RecipeCook] = []
}
