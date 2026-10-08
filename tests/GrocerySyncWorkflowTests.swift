import Foundation
import Observation

@MainActor
final class ControlledGroceries: GrocerySyncTransport {
    struct Read {
        let household: UUID
        let completion: CheckedContinuation<[GroceryItem], Error>
    }
    struct Write {
        let household: UUID
        let mutation: GroceryMutation
        let completion: CheckedContinuation<Void, Error>
    }
    var reads: [Read] = []
    var writes: [Write] = []
    func fetch(householdID: UUID) async throws -> [GroceryItem] {
        try await withCheckedThrowingContinuation { reads.append(Read(household: householdID, completion: $0)) }
    }
    func write(_ mutation: GroceryMutation, householdID: UUID) async throws {
        try await withCheckedThrowingContinuation { writes.append(Write(household: householdID, mutation: mutation, completion: $0)) }
    }
}

@main
struct GrocerySyncWorkflowTests {
    enum Failure: Error { case offline }

    @MainActor
    static func until(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for controlled operation")
            await Task.yield()
        }
    }

    @MainActor
    static func main() async throws {
        await rapidTapsAndSnapshots()
        await failedWriteAndReadRecovery()
        await householdLifetime()
        await insertionAndDeletion()
        await editOrderAndAisles()
        try await sharedRefresh()
        try await explicitRefreshFailure()
        print("Grocery sync workflow tests passed")
    }

    @MainActor
    static func rapidTapsAndSnapshots() async {
        let remote = ControlledGroceries()
        let milk = GroceryItem(name: "Milk", amount: "1", source: "General", position: 0)
        let sync = GrocerySync(transport: remote)
        sync.setHousehold(UUID(), items: [milk])
        sync.toggle(milk.id)
        sync.toggle(milk.id)
        precondition(!sync.items[0].isComplete, "Both taps must be visible synchronously")
        await until { remote.writes.count == 1 }
        sync.requestReload()
        await until { remote.reads.count == 1 }
        var otherShopper = milk
        otherShopper.amount = "2"
        remote.reads[0].completion.resume(returning: [otherShopper])
        await until { sync.items[0].amount == "2" }
        precondition(!sync.items[0].isComplete, "A snapshot preserves the newest pending tap and remote text")
        // Start a snapshot before the write acknowledgment, then finish it afterwards.
        sync.requestReload()
        await until { remote.reads.count == 2 }
        remote.writes[0].completion.resume()
        await until { remote.writes.count == 2 }
        // Scheduling another refresh shares the in-flight read; it does not create a parallel one.
        sync.requestReload()
        var stale = milk
        stale.isComplete = true
        remote.reads[1].completion.resume(returning: [stale])
        await until { remote.reads.count == 3 }
        precondition(!sync.items[0].isComplete && sync.items[0].amount == "2", "Reject snapshots spanning write acknowledgments")
        remote.reads[2].completion.resume(returning: [otherShopper])
        // The second write is still pending, so the snapshot merges its overlay.
        await until { sync.items[0].amount == "2" && !sync.items[0].isComplete }
        remote.writes[1].completion.resume()
        await until { remote.reads.count == 4 }
        remote.reads[3].completion.resume(returning: [otherShopper])
        sync.setHousehold(nil)
        if case let .edit(_, first) = remote.writes[0].mutation,
           case let .edit(_, second) = remote.writes[1].mutation {
            precondition(first.isComplete == true && second.isComplete == false, "Transport sees tap order")
        } else { preconditionFailure("Expected checkmark writes") }
    }

    @MainActor
    static func failedWriteAndReadRecovery() async {
        let remote = ControlledGroceries()
        let milk = GroceryItem(name: "Milk", amount: "1", source: "General", position: 0)
        var errors = 0
        var retry: CheckedContinuation<Void, Error>?
        let sync = GrocerySync(transport: remote, onError: { _ in errors += 1 }, retryDelay: {
            try await withCheckedThrowingContinuation { retry = $0 }
        })
        sync.setHousehold(UUID(), items: [milk])
        sync.toggle(milk.id)
        await until { remote.writes.count == 1 }
        remote.writes[0].completion.resume(throwing: Failure.offline)
        await until { remote.reads.count == 1 }
        remote.reads[0].completion.resume(throwing: Failure.offline)
        await until { retry != nil }
        precondition(errors == 2, "Report failed write and first reload failure")
        retry?.resume(); retry = nil
        await until { remote.reads.count == 2 }
        remote.reads[1].completion.resume(returning: [milk])
        await until { !sync.items[0].isComplete }
        precondition(errors == 2, "Recovery does not require a new realtime event")
        sync.setHousehold(nil)
    }

    @MainActor
    static func householdLifetime() async {
        let remote = ControlledGroceries()
        let old = UUID(), new = UUID()
        let milk = GroceryItem(name: "Milk", amount: "1", source: "General", position: 0)
        let bread = GroceryItem(name: "Bread", amount: "1", source: "General", position: 0)
        var errors = 0
        let sync = GrocerySync(transport: remote, onError: { _ in errors += 1 })
        sync.setHousehold(old, items: [milk])
        sync.toggle(milk.id)
        sync.toggle(milk.id)
        sync.requestReload()
        await until { remote.writes.count == 1 && remote.reads.count == 1 }
        sync.setHousehold(new, items: [bread])
        sync.toggle(bread.id)
        sync.requestReload()
        await until { remote.writes.count == 2 && remote.reads.count == 2 }
        // The adapter deliberately ignores cancellation to model late network completions.
        remote.writes[0].completion.resume(throwing: Failure.offline)
        remote.reads[0].completion.resume(returning: [milk])
        remote.writes[1].completion.resume()
        remote.reads[1].completion.resume(returning: [bread])
        await until { remote.reads.count == 3 }
        var checkedBread = bread; checkedBread.isComplete = true
        remote.reads[2].completion.resume(returning: [checkedBread])
        await until { sync.items.first?.isComplete == true }
        precondition(sync.items.map(\.id) == [bread.id] && errors == 0, "Old household cannot publish items or errors")
        precondition(remote.writes.map(\.household) == [old, new], "Cancel queued old writes without blocking new household")
        sync.setHousehold(nil)
    }

    @MainActor
    static func editOrderAndAisles() async {
        let remote = ControlledGroceries()
        var milk = GroceryItem(name: "Milk", amount: "1", source: "General", position: 0)
        milk.aisle = "dairy"
        let bread = GroceryItem(name: "Bread", amount: "1", source: "General", position: 1)
        let sync = GrocerySync(transport: remote)
        sync.setHousehold(UUID(), items: [milk, bread])
        var edited = milk; edited.name = "Oat milk"
        sync.toggle(milk.id)
        sync.update(edited, original: milk)
        sync.reorder([bread, milk]) // Caller values predate the rename and checkmark.
        precondition(sync.items[1].name == "Oat milk" && sync.items[1].isComplete && sync.items[1].aisle == nil,
            "Position writes must preserve current item fields")
        precondition(sync.assignAisles(["Milk": "dairy"]).isEmpty, "Ignore classification for an old name")
        let assigned = sync.assignAisles(["Oat milk": "dairy", "Bread": "bakery"])
        precondition(assigned.count == 2)
        precondition(sync.assignAisles(["Oat milk": "produce"]).isEmpty, "Do not replace an existing aisle")
        sync.requestReload()
        await until { remote.writes.count == 1 && remote.reads.count == 1 }
        for index in 0..<4 {
            remote.writes[index].completion.resume()
            if index < 3 { await until { remote.writes.count == index + 2 } }
        }
        await until { !remote.reads.isEmpty }
        // Flush a fetch that may have started during the serialized writes.
        remote.reads[0].completion.resume(returning: [])
        await until { remote.reads.count == 2 }
        var finalMilk = edited; finalMilk.isComplete = true; finalMilk.position = 1; finalMilk.aisle = "dairy"
        var finalBread = bread; finalBread.position = 0; finalBread.aisle = "bakery"
        remote.reads[1].completion.resume(returning: [finalMilk, finalBread])
        await until { sync.items.first?.id == bread.id && sync.items[1].aisle == "dairy" }
        // A stale editor must not recreate an item deleted remotely.
        sync.requestReload()
        await until { remote.reads.count == 3 }
        remote.reads[2].completion.resume(returning: [finalBread])
        await until { sync.items.count == 1 }
        sync.update(edited, original: milk)
        precondition(sync.items.count == 1 && remote.writes.count == 4)
        sync.setHousehold(nil)
    }

    @MainActor
    static func insertionAndDeletion() async {
        let remote = ControlledGroceries()
        let milk = GroceryItem(name: "Milk", amount: "1", source: "General", position: 7)
        var publications = 0
        let sync = GrocerySync(transport: remote, onChange: { publications += 1 })
        sync.setHousehold(UUID(), items: [milk])
        sync.add(name: "Bread")
        let bread = sync.items[1]
        precondition(bread.position == 8)
        sync.remove([milk.id])
        sync.requestReload()
        await until { remote.writes.count == 1 && remote.reads.count == 1 }
        remote.reads[0].completion.resume(returning: [milk])
        // The pending insert remains and the pending deletion stays hidden.
        await until { publications == 4 }
        precondition(sync.items.map(\.id) == [bread.id])
        remote.writes[0].completion.resume()
        await until { remote.writes.count == 2 && remote.reads.count == 2 }
        remote.writes[1].completion.resume()
        remote.reads[1].completion.resume(returning: [milk, bread])
        await until { remote.reads.count == 3 }
        remote.reads[2].completion.resume(returning: [bread])
        await until { sync.items.map(\.id) == [bread.id] }
        sync.setHousehold(nil)
    }

    @MainActor
    static func sharedRefresh() async throws {
        let remote = ControlledGroceries()
        let milk = GroceryItem(name: "Milk", amount: "1", source: "General", position: 0)
        let sync = GrocerySync(transport: remote)
        sync.setHousehold(UUID(), items: [milk])
        let refresh = Task { try await sync.refresh() }
        await until { remote.reads.count == 1 }
        sync.requestReload()
        precondition(remote.reads.count == 1, "Realtime refresh shares an existing full refresh")
        remote.reads[0].completion.resume(returning: [])
        await until { remote.reads.count == 2 }
        precondition(sync.items.map(\.id) == [milk.id], "An event invalidates the in-flight snapshot")
        var newer = milk; newer.amount = "2"
        remote.reads[1].completion.resume(returning: [newer])
        try await refresh.value
        precondition(sync.items[0].amount == "2", "Full refresh waits for the accepted replacement snapshot")
        let data = try JSONEncoder().encode(GroceryFields(isComplete: true))
        let fields = try JSONSerialization.jsonObject(with: data) as! [String: Bool]
        precondition(fields == ["is_complete": true], "A checkmark write must omit every unrelated field")
        sync.setHousehold(nil)
    }

    @MainActor
    static func explicitRefreshFailure() async throws {
        let remote = ControlledGroceries()
        let sync = GrocerySync(transport: remote)
        sync.setHousehold(UUID())
        let refresh = Task { try await sync.refresh() }
        await until { remote.reads.count == 1 }
        remote.reads[0].completion.resume(throwing: Failure.offline)
        do { try await refresh.value; preconditionFailure("An explicit refresh must surface failure") }
        catch Failure.offline { }
        sync.setHousehold(nil)
    }
}
