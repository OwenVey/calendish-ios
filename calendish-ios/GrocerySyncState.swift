import Foundation

/// Overlays only fields being saved locally, so another shopper's changes remain visible.
struct GrocerySyncState {
    enum Change {
        case insert(GroceryItem)
        case edit(UUID, name: String?, amount: String?, source: String?, isComplete: Bool?, position: Double?)
        case delete(UUID)

        func apply(to items: inout [GroceryItem]) {
            switch self {
            case .insert(let item):
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
                else { items.append(item) }
            case let .edit(id, name, amount, source, isComplete, position):
                guard let index = items.firstIndex(where: { $0.id == id }) else { return }
                if let name { items[index].name = name }
                if let amount { items[index].amount = amount }
                if let source { items[index].source = source }
                if let isComplete { items[index].isComplete = isComplete }
                if let position { items[index].position = position }
            case .delete(let id): items.removeAll { $0.id == id }
            }
        }
    }

    private var pending: [(id: UUID, changes: [Change])] = []
    private(set) var revision: UInt64 = 0

    mutating func invalidate() { revision &+= 1 }

    mutating func begin(_ changes: [Change]) -> UUID {
        let id = UUID()
        pending.append((id, changes))
        invalidate()
        return id
    }

    mutating func finish(_ id: UUID) {
        pending.removeAll { $0.id == id }
        invalidate()
    }

    func merging(_ serverItems: [GroceryItem]) -> [GroceryItem] {
        var items = serverItems
        for operation in pending {
            for change in operation.changes { change.apply(to: &items) }
        }
        return items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
