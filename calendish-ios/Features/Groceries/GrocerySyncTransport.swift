import Foundation

/// The internal transport seam has a Supabase adapter and a controlled test adapter.
@MainActor
protocol GrocerySyncTransport {
    func fetch(householdID: UUID) async throws -> [GroceryItem]
    func write(_ mutation: GroceryMutation, householdID: UUID) async throws
}
