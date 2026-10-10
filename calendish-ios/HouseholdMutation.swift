import Foundation

/// Commands describe member actions, rather than table operations. The adapter owns encoding and cleanup.
enum HouseholdMutation {
    case renameHousehold(UUID, String)
    case renameMember(household: UUID, user: UUID, name: String)
    case avatar(household: UUID, user: UUID, url: URL)
    case transferOwnership(household: UUID, user: UUID)
    case removeMember(household: UUID, user: UUID)
    case saveRecipe(Recipe, isNew: Bool, upload: HouseholdPhotoUpload?, stalePhoto: String?)
    case deleteRecipe(UUID)
    case sharing(UUID, Bool)
    case favorite(recipe: UUID, user: UUID, enabled: Bool)
    case review(RecipeReview)
    case markCooked(household: UUID, recipe: UUID, day: Date)
    case removeCooked(household: UUID, recipe: UUID, day: Date)
    case saveMeal(PlannedMeal, household: UUID, keepVersion: Bool)
    case updateMeal(UUID)
    case removeMeal(UUID)
    case saveNote(MealPlanNote, household: UUID)
    case removeNote(UUID)

    var failureAction: String {
        switch self {
        case .renameHousehold: "save the household name"
        case .renameMember: "save your name"
        case .avatar: "save your profile photo"
        case .transferOwnership: "confirm the ownership transfer"
        case .removeMember: "confirm member removal"
        case .saveRecipe: "confirm the recipe save"
        case .deleteRecipe: "confirm recipe deletion"
        case .sharing: "confirm recipe sharing"
        case .favorite: "update favorites"
        case .review: "save your recipe note or rating"
        case .markCooked, .removeCooked: "update cooking history"
        case .saveMeal, .updateMeal, .removeMeal: "confirm the meal plan change"
        case .saveNote, .removeNote: "confirm the meal-plan note change"
        }
    }
    var failureRecovery: String {
        switch self {
        case .saveRecipe: "Check the recipe in your collection before trying again. Reopen the editor to review your draft."
        default: "Check the current data before trying again."
        }
    }
}
