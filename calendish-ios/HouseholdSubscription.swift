import Foundation

@MainActor
protocol HouseholdSubscription: AnyObject {
    var isConnected: Bool { get }
    var changes: AsyncStream<HouseholdChange> { get }
    func cancel() async
}
