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
                ForEach(review.sections(groceries: store.groceries, units: units)) { candidate in
                    section(for: candidate)
                }
                if review.isEmpty {
                    ContentUnavailableView("No Meals Planned Here Yet", systemImage: "calendar", description: Text("Plan a meal to review its ingredients."))
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Add to Groceries").navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(review.ingredientCount == 0 ? "" : "\(review.selected.count) of \(review.ingredientCount) selected")
            .sensoryFeedback(.selection, trigger: review.selected)
            .sensoryFeedback(.selection, trigger: review.servings)
            .onAppear { review.prepare(groceries: store.groceries, units: units) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.toolbarGlyph() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: add) { OnAccentLabel(title: "Add") }
                        .disabled(review.selected.isEmpty).modifier(GlassActionStyle(prominent: true))
                        .accessibilityLabel(review.selected.count == 1 ? "Add 1 item" : "Add \(review.selected.count) items")
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
                            Text("On List").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            if candidate.lines.isEmpty {
                Text("This recipe has no ingredients.").foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.title).font(.headline).foregroundStyle(.primary).textCase(nil)
                Spacer()
                if !candidate.lines.isEmpty {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        review.toggleRecipe(candidate.id)
                    }
                    .font(.subheadline).textCase(nil)
                    .accessibilityLabel(allSelected ? "Deselect all \(candidate.title) ingredients" : "Select all \(candidate.title) ingredients")
                }
            }
        } footer: {
            if onListCount == candidate.lines.count, !candidate.lines.isEmpty {
                Text("These ingredients are already on your grocery list, so none are selected.")
            } else if onListCount > 0 {
                Text("Ingredients already on your grocery list aren’t selected.")
            }
        }
    }

    private func servingsStepper(for candidate: GroceryImportReview.Section) -> some View {
        let original = candidate.originalServings
        return HStack(spacing: 12) {
            Label {
                Text("\(candidate.servings) servings").monospacedDigit().contentTransition(.numericText(value: Double(candidate.servings)))
            } icon: { Image(systemName: "person.2") }
            if candidate.servings != original {
                Button("Reset") { review.resetServings(for: candidate.id) }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset to \(original) servings")
                    .transition(.opacity)
            }
            Spacer()
            Stepper("Servings", value: Binding(get: { candidate.servings }, set: { review.setServings($0, for: candidate.id) }), in: 1...100)
                .labelsHidden()
                .accessibilityValue("\(candidate.servings) servings")
        }
        .animation(reduceMotion ? nil : .snappy, value: candidate.servings)
    }

    private func add() {
        store.importGroceries(review.groceriesToAdd(groceries: store.groceries, units: units))
        dismiss()
    }
}
