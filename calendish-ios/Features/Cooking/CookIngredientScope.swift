import Foundation

/// Which ingredients cook mode's panel lists.
enum CookIngredientScope: String, CaseIterable, Identifiable {
    case all = "All ingredients"
    case currentStep = "Current step"
    var id: Self { self }

    /// The filter button's label, beside the "Ingredients" heading.
    var shortTitle: String {
        switch self {
        case .all: "All"
        case .currentStep: "Current step"
        }
    }
}
