import Foundation

/// A database rejection is definitive; transport failures may follow a committed household move.
struct HouseholdMoveRejected: LocalizedError {
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}
