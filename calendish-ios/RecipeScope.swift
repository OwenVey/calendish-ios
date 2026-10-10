import Foundation

/// The Recipes browser's ownership filters. Mine and Household overlap for a recipe the person shares.
enum RecipeScope: String, CaseIterable, Identifiable {
    case all, mine, household
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .mine: "Mine"
        case .household: "Household"
        }
    }

    func includes(_ recipe: Recipe, person: UUID?) -> Bool {
        switch (self, recipe.owner) {
        case (.all, _): true
        case (.mine, .person(let owner, _)?): owner == person
        case (.household, .household?): true
        case (.household, .person(_, let shared)?): shared
        default: false
        }
    }
}
