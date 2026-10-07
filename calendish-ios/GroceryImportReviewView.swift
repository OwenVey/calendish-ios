import SwiftUI

struct GroceryImportCandidate: Identifiable {
    var recipe: Recipe
    var servings: Int
    var id: UUID { recipe.id }

    /// Scale recognized leading quantities; keep free-form instructions intact for review.
    var ingredientLines: [String] {
        guard recipe.servings > 0 else { return recipe.ingredients.map(\.text) }
        return recipe.ingredients.map { $0.scaled(by: Double(servings) / Double(recipe.servings)) }
    }
}

struct GroceryImportReviewView: View {
    let candidates: [GroceryImportCandidate]
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []
    private var selectedCandidates: [GroceryImportCandidate] { candidates.filter { selected.contains($0.id) } }
    private var ingredientCount: Int { selectedCandidates.reduce(0) { $0 + $1.ingredientLines.count } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose what you’re shopping for.").font(.headline)
                    Text("Review quantities before adding. Repeated meals use the largest planned serving count. Free-form quantities stay as written; adjust them in Groceries if needed.")
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
                                Image(systemName: active || selected.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(candidate.id) && !active ? CalendishStyle.accent : Color.secondary).font(.title3).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.recipe.title).font(.headline).foregroundStyle(.primary)
                                    Text(active ? "Already on the grocery list" : "\(candidate.servings) servings · \(candidate.recipe.ingredients.count) ingredients")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8)
                        }.buttonStyle(.plain).disabled(active || candidate.recipe.ingredients.isEmpty)
                            .accessibilityValue(active ? "Already added" : (selected.contains(candidate.id) ? "Selected" : "Not selected"))
                            .accessibilityAddTraits(selected.contains(candidate.id) ? .isSelected : [])
                    }
                    if candidates.isEmpty {
                        ContentUnavailableView("No Meals Planned Here Yet", systemImage: "calendar", description: Text("Plan a meal to review its ingredients."))
                    }
                }
                ForEach(selectedCandidates) { candidate in
                    Section("\(candidate.recipe.title) · \(candidate.servings) servings") {
                        ForEach(Array(candidate.ingredientLines.enumerated()), id: \.offset) { _, line in Text(line) }
                    }
                }
            }
            .navigationTitle("Add to Groceries").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.toolbarGlyph() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let start = (store.groceries.map(\.position).max() ?? 0) + 1
                        var items: [GroceryItem] = []
                        for candidate in selectedCandidates {
                            for line in candidate.ingredientLines {
                                items.append(GroceryItem(name: line, amount: "", source: candidate.recipe.title, position: start + Double(items.count)))
                            }
                        }
                        store.importGroceries(items)
                        dismiss()
                    }.disabled(ingredientCount == 0).modifier(GlassActionStyle(prominent: true))
                }
            }
        }
    }
}
