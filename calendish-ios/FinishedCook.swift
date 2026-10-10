import Foundation

/// A cook finished in Cook Mode, waiting to become a marked cook.
struct FinishedCook: Codable, Hashable {
    var recipeID: UUID
    /// The day cooking started, so a late dinner finished after midnight counts for its evening.
    var day: Date
    var accountID: UUID?

    init(recipeID: UUID, startedAt: Date, accountID: UUID?) {
        self.recipeID = recipeID
        day = Calendar.current.startOfDay(for: startedAt)
        self.accountID = accountID
    }
}
