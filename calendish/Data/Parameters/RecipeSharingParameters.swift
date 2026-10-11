import Foundation

nonisolated struct RecipeSharingParameters: Encodable, Sendable {
    var target_recipe: UUID
    var shared: Bool
}
