import SwiftUI

struct GroceryImportReviewView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    @State private var review: GroceryImportReview

    init(candidates: [GroceryImportCandidate]) {
        _review = State(initialValue: GroceryImportReview(candidates: candidates))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(review.sections(groceries: store.groceries.items, units: units)) { candidate in
                    section(for: candidate)
                }
                if review.isEmpty {
                    ContentUnavailableView("No meals planned here yet", systemImage: "calendar", description: Text("Plan a meal to review its ingredients."))
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Add to groceries").navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(review.ingredientCount == 0 ? "" : "\(review.selected.count) of \(review.ingredientCount) selected")
            .sensoryFeedback(.selection, trigger: review.selected)
            .sensoryFeedback(.selection, trigger: review.servings)
            .onAppear { review.prepare(groceries: store.groceries.items, units: units) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.toolbarGlyph() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: add) { OnAccentLabel(title: "Add") }
                        .disabled(review.selected.isEmpty).modifier(GlassActionStyle(prominent: true))
                        .accessibilityLabel("Add selected ingredients")
                }
            }
        }
    }

    private func section(for candidate: GroceryImportReview.Section) -> some View {
        let allSelected = candidate.allSelected
        let onListCount = candidate.onListCount
        return Section {
            // Recipes without a serving count can't be scaled.
            if candidate.canScale {
                servingsStepper(for: candidate)
            }
            ForEach(candidate.lines) { ingredient in
                let isSelected = ingredient.isSelected
                Button {
                    review.toggleIngredient(ingredient.id)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? CalendishStyle.accent : Color.secondary).font(.title3).accessibilityHidden(true)
                        Text(ingredient.text).foregroundStyle(isSelected ? .primary : .secondary)
                        if ingredient.isOnList {
                            Spacer(minLength: 8)
                            Text("On list").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityLabel(ingredient.text + (ingredient.isOnList ? ". Already on list" : ""))
                .accessibilityHint(ingredient.isOnList && !isSelected ? "Select to add more. Quantities may differ." : "")
            }
            if candidate.lines.isEmpty {
                Text("This recipe has no ingredients.").foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.title).font(.headline).foregroundStyle(.primary).textCase(nil)
                Spacer()
                if !candidate.lines.isEmpty {
                    Button(allSelected ? "Deselect all" : "Select all") {
                        review.toggleRecipe(candidate.id)
                    }
                    .font(.subheadline).textCase(nil)
                    .accessibilityLabel(allSelected ? "Deselect all \(candidate.title) ingredients" : "Select all \(candidate.title) ingredients")
                }
            }
        } footer: {
            if onListCount > 0 {
                Text("On list matches an unchecked item for this recipe. Quantities may differ. Matching ingredients start unselected. Select them to add more.")
            }
            if candidate.plannedOccurrences > 1 {
                Text("Planned more than once. This amount uses the largest serving count for one meal, not the total for the week.")
            }
        }
    }

    private func servingsStepper(for candidate: GroceryImportReview.Section) -> some View {
        let original = candidate.originalServings
        return HStack(spacing: 12) {
            Label {
                Text(InterfaceCopy.servings(candidate.servings)).monospacedDigit().contentTransition(.numericText(value: Double(candidate.servings)))
            } icon: { Image(systemName: "person.2") }
            if candidate.servings != original {
                Button("Reset") { review.resetServings(for: candidate.id) }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset to \(InterfaceCopy.servings(original))")
                    .transition(.opacity)
            }
            Spacer()
            Stepper("Servings", value: Binding(get: { candidate.servings }, set: { review.setServings($0, for: candidate.id) }), in: 1...100)
                .labelsHidden()
                .accessibilityValue(InterfaceCopy.servings(candidate.servings))
        }
        .animation(reduceMotion ? nil : .snappy, value: candidate.servings)
    }

    private func add() {
        store.groceries.applyImport(review.groceriesToAdd(groceries: store.groceries.items, units: units))
        dismiss()
    }
}
