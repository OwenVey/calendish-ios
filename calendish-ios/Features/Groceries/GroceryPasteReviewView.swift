import SwiftUI

struct GroceryPasteReviewView: View {
    @Environment(HouseholdStore.self) private var store
    @State var items: [GroceryItem]
    let onAdded: () -> Void

    private var reviewedItems: [GroceryItem] {
        items.compactMap { item in
            var item = item
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return item.name.isEmpty ? nil : item
        }
    }

    var body: some View {
        let reviewed = reviewedItems
        List {
            Section {
                ForEach($items) { $item in
                    TextField("Item", text: $item.name, axis: .vertical)
                        .accessibilityLabel("Grocery item")
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
                    let start = store.groceries.items.map(\.position).max() ?? 0
                    let positioned = reviewed.enumerated().map { index, item in
                        var item = item
                        item.position = start + Double(index + 1)
                        return item
                    }
                    store.groceries.insert(positioned)
                    onAdded()
                } label: {
                    OnAccentLabel(title: reviewed.count == 1 ? "Add 1 item" : "Add \(reviewed.count) items")
                }
                .disabled(reviewed.isEmpty)
                .modifier(GlassActionStyle(prominent: true))
            }
        }
    }
}
