import Foundation

@main
struct GrocerySyncTests {
    static func main() {
        let milk = GroceryItem(name: "Milk", amount: "1", source: "General", position: 0)
        let bread = GroceryItem(name: "Bread", amount: "1", source: "General", position: 1)
        var sync = GrocerySyncState()
        let before = sync.revision
        let check = sync.begin([.edit(milk.id, name: nil, amount: nil, source: nil, isComplete: true, position: nil)])
        precondition(before != sync.revision, "A local write must invalidate an in-flight snapshot")
        var remoteMilk = milk
        remoteMilk.amount = "2"
        var remoteBread = bread
        remoteBread.isComplete = true
        var result = sync.merging([remoteMilk, remoteBread])
        precondition(result[0].isComplete && result[0].amount == "2", "Pending checkmarks must preserve remote text edits")
        precondition(result[1].isComplete, "Another shopper's checkmark must appear during a pending save")

        let uncheck = sync.begin([.edit(milk.id, name: nil, amount: nil, source: nil, isComplete: false, position: nil)])
        sync.finish(check)
        result = sync.merging([remoteMilk, remoteBread])
        precondition(!result[0].isComplete, "Acknowledging an earlier tap must preserve the latest tap")
        sync.finish(uncheck)
        remoteMilk.isComplete = true
        precondition(sync.merging([remoteMilk])[0].isComplete, "Once writes finish, the server is authoritative")

        let eggs = GroceryItem(name: "Eggs", amount: "12", source: "General", position: 2)
        let add = sync.begin([.insert(eggs)])
        precondition(sync.merging([milk, bread]).count == 3, "Pending additions must survive a remote snapshot")
        precondition(sync.merging([milk, bread, eggs]).count == 3, "An echoed insert must not duplicate an item")
        sync.finish(add)
        let delete = sync.begin([.delete(milk.id)])
        precondition(!sync.merging([milk, bread]).contains { $0.id == milk.id }, "Pending deletions must not reappear")
        sync.finish(delete)

        let reorder = sync.begin([.edit(bread.id, name: nil, amount: nil, source: nil, isComplete: nil, position: -1)])
        result = sync.merging([milk, remoteBread])
        precondition(result[0].id == bread.id && result[0].isComplete, "Reordering must preserve remote checkmarks")
        sync.finish(reorder)
        let edit = sync.begin([.edit(bread.id, name: "Whole wheat", amount: nil, source: nil, isComplete: nil, position: nil)])
        precondition(sync.merging([remoteBread])[0].isComplete, "Text edits must preserve remote checkmarks")
        precondition(sync.merging([]).isEmpty, "An update must not resurrect a remotely deleted item")
        let revision = sync.revision
        sync.finish(edit)
        precondition(sync.revision != revision, "Write completion must invalidate snapshots started before acknowledgment")

        var sortedBread = remoteBread
        sortedBread.aisle = "bakery"
        let sort = sync.begin([.sort(milk.id, aisle: "dairy")])
        result = sync.merging([milk, sortedBread])
        precondition(result[0].aisle == "dairy" && result[1].aisle == "bakery", "A pending aisle must show before the server echoes it")
        sync.finish(sort)
        let rename = sync.begin([.edit(bread.id, name: "Rye", amount: nil, source: nil, isComplete: nil, position: nil)])
        precondition(sync.merging([sortedBread])[0].aisle == nil, "A pending rename must clear the old aisle")
        sync.finish(rename)
        print("Grocery sync tests passed")
    }
}
