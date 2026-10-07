import SwiftUI

struct GroceryImportCandidate: Identifiable {
    var recipe: Recipe
    var servings: Int
    var id: UUID { recipe.id }
}

struct GroceryImportReviewView: View {
    let candidates: [GroceryImportCandidate]
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose what you’re shopping for.").font(.headline)
                    Text("Ingredients are added only when you confirm. Repeated meals use the largest planned serving count.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
                Section("Recipes") {
                    ForEach(candidates) { candidate in
                        let active = store.groceries.contains { $0.source == candidate.recipe.title }
                        Button {
                            if selected.contains(candidate.id) { selected.remove(candidate.id) }
                            else { selected.insert(candidate.id) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: active ? "checkmark.circle.fill" : (selected.contains(candidate.id) ? "checkmark.circle.fill" : "circle"))
                                    .foregroundStyle(active ? Color.secondary : CalendishStyle.accent).font(.title3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.recipe.title).font(.headline).foregroundStyle(.primary)
                                    Text(active ? "Already on the grocery list" : "\(candidate.servings) servings · \(candidate.recipe.ingredients.count) ingredients")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8)
                        }.buttonStyle(.plain).disabled(active)
                    }
                    if candidates.isEmpty {
                        ContentUnavailableView("No meals planned here yet", systemImage: "calendar", description: Text("Plan a meal to review its ingredients."))
                    }
                }
                Section {
                    Label("Import is not connected in this preview.", systemImage: "info.circle").foregroundStyle(.secondary)
                } footer: {
                    Text("The next build will save ingredient snapshots, preserve their recipe sources, and offer undo.")
                }
            }
            .navigationTitle("Add to groceries").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { }.disabled(true) }
            }
        }
    }
}
