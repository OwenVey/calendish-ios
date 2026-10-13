import Foundation

/// The server's answer when adding one dinner from a meal plan proposal.
nonisolated enum PlannedMealAddition: String, Decodable, Sendable {
    case added
    /// A meal with this ID was saved earlier, such as before a lost response.
    case alreadyAdded = "already_added"
    /// The day gained a recipe or note since the proposal was made, so nothing was added.
    case occupied
    /// The recipe was edited since it was reviewed, so nothing was added.
    case changed
    /// The recipe was deleted or is no longer available to the person.
    case unavailable
}
