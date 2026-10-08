import SwiftUI

struct GroceryImportCandidate: Identifiable {
    var recipe: Recipe
    var servings: Int
    var id: UUID { recipe.id }

    /// Scale recognized leading quantities; keep free-form instructions intact for review.
    var ingredientLines: [(id: UUID, text: String)] {
        guard recipe.servings > 0 else { return recipe.ingredients.map { ($0.id, Ingredient.convert($0.text, to: .current)) } }
        let units = MeasurementPreference.current
        return recipe.ingredients.map { ($0.id, $0.display(scale: Double(servings) / Double(recipe.servings), units: units)) }
    }
}

struct GroceryImportReviewView: View {
    let candidates: [GroceryImportCandidate]
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Selected ingredient IDs, seeded once on appear so later list changes don't reset the user's choices.
    @State private var selected: Set<UUID> = []
    @State private var seeded = false
    /// Servings changed in this sheet, by recipe ID; the rest keep the count they came in with.
    @State private var servings: [UUID: Int] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ingredientCount: Int { candidates.reduce(0) { $0 + $1.recipe.ingredients.count } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(adjustedCandidates) { candidate in
                    section(for: candidate)
                }
                if candidates.isEmpty {
                    ContentUnavailableView("No Meals Planned Here Yet", systemImage: "calendar", description: Text("Plan a meal to review its ingredients."))
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Add to Groceries").navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(ingredientCount == 0 ? "" : "\(selected.count) of \(ingredientCount) selected")
            .sensoryFeedback(.selection, trigger: selected)
            .sensoryFeedback(.selection, trigger: servings)
            .onAppear {
                guard !seeded else { return }
                seeded = true
                for candidate in candidates {
                    selected.formUnion(Set(candidate.recipe.ingredients.map(\.id)).subtracting(ingredientsOnList(candidate)))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.toolbarGlyph() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: add) { OnAccentLabel(title: "Add") }
                        .disabled(selected.isEmpty).modifier(GlassActionStyle(prominent: true))
                        .accessibilityLabel(selected.count == 1 ? "Add 1 item" : "Add \(selected.count) items")
                }
            }
        }
    }

    private var adjustedCandidates: [GroceryImportCandidate] {
        candidates.map { GroceryImportCandidate(recipe: $0.recipe, servings: servings[$0.id] ?? $0.servings) }
    }

    private func section(for candidate: GroceryImportCandidate) -> some View {
        let ids = candidate.recipe.ingredients.map(\.id)
        let allSelected = !ids.isEmpty && ids.allSatisfy(selected.contains)
        let onList = ingredientsOnList(candidate)
        return Section {
            // Recipes without a serving count can't be scaled.
            if candidate.recipe.servings > 0, !ids.isEmpty {
                servingsStepper(for: candidate)
            }
            ForEach(candidate.ingredientLines, id: \.id) { ingredient in
                let isSelected = selected.contains(ingredient.id)
                Button {
                    if isSelected { selected.remove(ingredient.id) } else { selected.insert(ingredient.id) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? CalendishStyle.accent : Color.secondary).font(.title3).accessibilityHidden(true)
                        Text(ingredient.text).foregroundStyle(isSelected ? .primary : .secondary)
                        if onList.contains(ingredient.id) {
                            Spacer(minLength: 8)
                            Text("On List").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            if ids.isEmpty {
                Text("This recipe has no ingredients.").foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.recipe.title).font(.headline).foregroundStyle(.primary).textCase(nil)
                Spacer()
                if !ids.isEmpty {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        if allSelected { selected.subtract(ids) } else { selected.formUnion(ids) }
                    }
                    .font(.subheadline).textCase(nil)
                    .accessibilityLabel(allSelected ? "Deselect all \(candidate.recipe.title) ingredients" : "Select all \(candidate.recipe.title) ingredients")
                }
            }
        } footer: {
            if onList.count == ids.count, !ids.isEmpty {
                Text("These ingredients are already on your grocery list, so none are selected.")
            } else if !onList.isEmpty {
                Text("Ingredients already on your grocery list aren’t selected.")
            }
        }
    }

    private func servingsStepper(for candidate: GroceryImportCandidate) -> some View {
        let original = candidates.first { $0.id == candidate.id }?.servings ?? candidate.servings
        return HStack(spacing: 12) {
            Label {
                Text("\(candidate.servings) servings").monospacedDigit().contentTransition(.numericText(value: Double(candidate.servings)))
            } icon: { Image(systemName: "person.2") }
            if candidate.servings != original {
                Button("Reset") { servings[candidate.id] = nil }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset to \(original) servings")
                    .transition(.opacity)
            }
            Spacer()
            Stepper("Servings", value: Binding(get: { candidate.servings }, set: { servings[candidate.id] = $0 }), in: 1...100)
                .labelsHidden()
                .accessibilityValue("\(candidate.servings) servings")
        }
        .animation(reduceMotion ? nil : .snappy, value: candidate.servings)
    }

    /// Ingredients this recipe already put on the list and that are still left to buy; checked-off ones were
    /// already shopped for. Compared by the food they name, so a rescaled or lightly edited item still counts.
    private func ingredientsOnList(_ candidate: GroceryImportCandidate) -> Set<UUID> {
        let names = Set(store.groceries.filter { $0.source == candidate.recipe.title && !$0.isComplete }.map { foodKey($0.name) })
        guard !names.isEmpty else { return [] }
        return Set(candidate.ingredientLines.filter { names.contains(foodKey($0.text)) }.map(\.id))
    }

    private func foodKey(_ line: String) -> String {
        let name = IngredientParser.name(of: line)
        return (name.isEmpty ? line : name).lowercased()
    }

    private func add() {
        let start = (store.groceries.map(\.position).max() ?? 0) + 1
        var items: [GroceryItem] = []
        for candidate in adjustedCandidates {
            for ingredient in candidate.ingredientLines where selected.contains(ingredient.id) {
                items.append(GroceryItem(name: ingredient.text, amount: "", source: candidate.recipe.title, position: start + Double(items.count)))
            }
        }
        store.importGroceries(items)
        dismiss()
    }
}
