import Foundation

@main
struct GroceryPasteTests {
    static func main() {
        let list = "  Milk  \r\n\r\n• 2 eggs\n- [ ] Bread\n[x] Apples\n☐ Butter\n1. Rice\n2) Beans\n\t\n-\n[ ]"
        let items = GroceryPaste.items(from: list)
        precondition(items.map(\.name) == ["Milk", "2 eggs", "Bread", "Apples", "Butter", "Rice", "Beans"],
                     "Copied bullets, numbered lists, checkboxes, and blank lines should become clean items")
        let quantities = GroceryPaste.items(from: "1.5 kg flour\n1/2 cup sugar\n2% milk\n12-pack soda\nSalt, pepper\nMilk\nMilk")
        precondition(quantities.map(\.name) == ["1.5 kg flour", "1/2 cup sugar", "2% milk", "12-pack soda", "Salt, pepper", "Milk", "Milk"],
                     "Quantities, punctuation, and repeated lines must remain available for review")
        precondition(Set(quantities.map(\.id)).count == quantities.count, "Repeated items need independent editable rows")
        precondition(GroceryPaste.items(from: "\n \r\n\t").isEmpty)
        print("Grocery paste tests passed")
    }
}
