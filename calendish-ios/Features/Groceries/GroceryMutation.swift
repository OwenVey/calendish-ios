import Foundation

/// One description drives both the local overlay and the remote write.
enum GroceryMutation {
    struct Position { let id: UUID; let value: Double }
    struct Aisle { let id: UUID; let name: String; let value: String }
    case insert([GroceryItem])
    case edit(UUID, GroceryFields)
    case delete([UUID])
    case reorder([Position])
    case sort([Aisle])

    var changes: [GrocerySyncState.Change] {
        switch self {
        case .insert(let items): items.map { .insert($0) }
        case let .edit(id, fields):
            [.edit(id, name: fields.name, amount: fields.amount, source: fields.source,
                isComplete: fields.isComplete, position: nil)]
        case .delete(let ids): ids.map { .delete($0) }
        case .reorder(let positions):
            positions.map { .edit($0.id, name: nil, amount: nil, source: nil, isComplete: nil, position: $0.value) }
        case .sort(let aisles): aisles.map { .sort($0.id, aisle: $0.value) }
        }
    }
}
