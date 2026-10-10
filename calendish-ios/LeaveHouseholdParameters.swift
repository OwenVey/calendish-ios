import Foundation

nonisolated struct LeaveHouseholdParameters: Encodable, Sendable {
    var save_household_recipes: Bool
    var expected_household: UUID?
}
