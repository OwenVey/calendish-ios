import SwiftUI

struct GroceryPasteReviewView: View {
    @Environment(HouseholdStore.self) private var store
    @State var items: [GroceryItem]
    let onAdded: () -> Void

    var body: some View {
        let count = GroceryItem.addableNames(items.map(\.name)).count
        List {
            Section {
                ForEach($items) { $item in
                    TextField("Item", text: $item.name, axis: .vertical)
                        .accessibilityLabel("Grocery item")
                        .accessibilityValue(item.name)
                }
                .onDelete { items.remove(atOffsets: $0) }
            } footer: {
                Text("Edit an item or swipe left to remove it. Blank items won’t be added.")
            }
        }
        .navigationTitle("Review items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    store.groceries.add(names: items.map(\.name))
                    onAdded()
                } label: {
                    OnAccentLabel(title: count == 1 ? "Add 1 item" : "Add \(count) items")
                }
                .disabled(count == 0)
                .modifier(GlassActionStyle(prominent: true))
            }
        }
    }
}
