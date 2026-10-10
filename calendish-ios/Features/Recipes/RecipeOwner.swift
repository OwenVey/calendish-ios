import Foundation

/// A personal recipe belongs to a person and follows them between households; sharing lets their
/// household use the same original. A household recipe belongs to the household, and every member edits it.
enum RecipeOwner: Hashable, Codable {
    case person(UUID, shared: Bool)
    case household

    var person: UUID? { if case .person(let id, _) = self { id } else { nil } }
    var isShared: Bool { if case .person(_, let shared) = self { shared } else { false } }
}
