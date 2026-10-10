import Foundation

/// The household a person ends up in after a move, and photos that nothing uses anymore.
nonisolated struct HouseholdMoveResult: Decodable, Sendable {
    var household: HouseholdRecord
    var unusedPhotos: [String]
    enum CodingKeys: String, CodingKey { case household, unusedPhotos = "unused_photos" }
}
