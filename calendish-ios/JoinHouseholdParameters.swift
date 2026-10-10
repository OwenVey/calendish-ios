import Foundation

nonisolated struct JoinHouseholdParameters: Encodable, Sendable {
    var code: String
    var save_household_recipes: Bool
    var expected_household: UUID?
}
