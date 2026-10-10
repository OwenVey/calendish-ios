import Foundation

/// A day a member recorded a recipe as cooked, by hand or by finishing Cook Mode.
struct RecipeCook: Hashable {
    var recipeID: UUID
    var date: Date
    var cookedBy: UUID?
}
