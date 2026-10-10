import Foundation

nonisolated struct StartHouseholdParameters: Encodable, Sendable {
    var member_name: String
    var code: String?
}
