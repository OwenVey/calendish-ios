import Foundation

@MainActor
final class MemoryHouseholdSubscription: HouseholdSubscription {
    let id = UUID()
    let household: UUID
    let user: UUID
    let changes: AsyncStream<HouseholdChange>
    private let continuation: AsyncStream<HouseholdChange>.Continuation
    private(set) var isConnected = true
    var onCancel: (() -> Void)?
    init(household: UUID, user: UUID) {
        self.household = household; self.user = user
        (changes, continuation) = AsyncStream.makeStream()
    }
    func emit(_ change: HouseholdChange) { if isConnected { continuation.yield(change) } }
    func cancel() async { isConnected = false; continuation.finish(); onCancel?(); onCancel = nil }
}
