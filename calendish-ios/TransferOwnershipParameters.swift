import Foundation

nonisolated struct TransferOwnershipParameters: Encodable, Sendable {
    var target_household: UUID
    var new_owner: UUID
}
