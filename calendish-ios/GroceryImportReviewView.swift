import SwiftUI

struct GroceryImportReviewView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original
    @State private var review: GroceryImportReview

    init(candidates: [GroceryImportCandidate]) {
        _review = State(initialValue: GroceryImportReview(candidates: candidates))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(review.sections(groceries: store.groceries.items, units: units)) { candidate in
                    GroceryImportSection(candidate: candidate, review: $review)
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

    private func add() {
        store.groceries.applyImport(review.groceriesToAdd(groceries: store.groceries.items, units: units))
        dismiss()
    }
}
