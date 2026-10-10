import Foundation

@MainActor
final class RecordingGroceries: GrocerySyncTransport {
    var lists: [UUID: [GroceryItem]] = [:]
    var failWrites = false
    func fetch(householdID: UUID) async throws -> [GroceryItem] { lists[householdID] ?? [] }
    func write(_ mutation: GroceryMutation, householdID: UUID) async throws {
        if failWrites { throw SpokenGroceryAddTests.Failure.offline }
        var items = lists[householdID] ?? []
        for change in mutation.changes { change.apply(to: &items) }
        lists[householdID] = items
    }
}

@main
struct SpokenGroceryAddTests {
    enum Failure: Error { case offline }
    static let person = UUID(), home = UUID()

    @MainActor
    static func adder(_ groceries: RecordingGroceries, signedIn: Bool = true, household: UUID? = home) -> SpokenGroceryAdd {
        SpokenGroceryAdd(userID: { signedIn ? person : nil },
                         household: { $0 == person ? household : nil },
                         transport: groceries)
    }

    @MainActor
    static func main() async throws {
        try await addsSpokenTextAsTyped()
        try await skipsItemsAlreadyOnList()
        await needsHousehold()
        await failedSaveIsNotConfirmed()
        try await ignoresBlankItems()
        print("Spoken grocery add tests passed")
    }

    @MainActor
    static func addsSpokenTextAsTyped() async throws {
        let groceries = RecordingGroceries()
        groceries.lists[home] = [GroceryItem(name: "Eggs", amount: "", source: "General", position: 4)]
        let outcomes = try await adder(groceries).add(["  2 cartons of oat milk "])
        precondition(outcomes == [.added("2 cartons of oat milk")])
        let added = groceries.lists[home]!.last!
        precondition(added.name == "2 cartons of oat milk" && added.amount == "" && added.source == "General")
        precondition(added.position == 5 && !added.isComplete)
    }

    @MainActor
    static func skipsItemsAlreadyOnList() async throws {
        let groceries = RecordingGroceries()
        groceries.lists[home] = [
            GroceryItem(name: "Oat milk ", amount: "", source: "General", position: 1),
            GroceryItem(name: "Apples", amount: "", source: "General", isComplete: true, position: 2),
        ]
        let outcomes = try await adder(groceries).add(["oat MILK", "apples", "Bread", "bread"])
        precondition(outcomes == [.alreadyOnList("oat MILK"), .added("apples"), .added("Bread"), .alreadyOnList("bread")])
        precondition(groceries.lists[home]!.map(\.name) == ["Oat milk ", "Apples", "apples", "Bread"])
    }

    @MainActor
    static func needsHousehold() async {
        let groceries = RecordingGroceries()
        for adder in [adder(groceries, signedIn: false), adder(groceries, household: nil)] {
            do { _ = try await adder.add(["Apples"]); preconditionFailure("Added without a household") }
            catch { precondition(error as? SpokenGroceryAdd.Failure == .noHousehold) }
        }
        precondition(groceries.lists.isEmpty)
    }

    @MainActor
    static func failedSaveIsNotConfirmed() async {
        let groceries = RecordingGroceries()
        groceries.failWrites = true
        do { _ = try await adder(groceries).add(["Apples"]); preconditionFailure("Confirmed an unsaved item") }
        catch { precondition(error is Failure) }
    }

    @MainActor
    static func ignoresBlankItems() async throws {
        let groceries = RecordingGroceries()
        let outcomes = try await adder(groceries).add(["", "  ", "Apples\n"])
        precondition(outcomes == [.added("Apples")])
        precondition(groceries.lists[home]!.map(\.name) == ["Apples"])
    }
}
