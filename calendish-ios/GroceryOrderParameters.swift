import Foundation

nonisolated struct GroceryOrderParameters: Encodable, Sendable {
    var target_household: UUID
    var item_ids: [UUID]
    var item_positions: [Double]
}
