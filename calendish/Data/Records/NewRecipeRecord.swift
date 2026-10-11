import Foundation

/// A new personal recipe. People only create personal recipes; household recipes come from sharing.
nonisolated struct NewRecipeRecord: Encodable, Sendable {
    var id: UUID
    var ownerID: UUID
    var isShared: Bool
    var content: RecipeContentRecord
    enum CodingKeys: String, CodingKey {
        case id, ownerID = "owner_id", isShared = "is_shared"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ownerID, forKey: .ownerID)
        try container.encode(isShared, forKey: .isShared)
        try content.encode(to: encoder)
    }
}
