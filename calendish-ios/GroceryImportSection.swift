import SwiftUI

/// One recipe or note in the grocery review: its servings and the ingredients to select.
struct GroceryImportSection: View {
    let candidate: GroceryImportReview.Section
    @Binding var review: GroceryImportReview

    var body: some View {
        Section {
            // Recipes without a serving count can't be scaled.
            if candidate.canScale {
                GroceryImportServingsStepper(candidate: candidate, review: $review)
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
                .accessibilityLabel(ingredient.isOnList ? "\(ingredient.text). Already on list" : ingredient.text)
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
                    Button(candidate.allSelected ? "Deselect all" : "Select all") {
                        review.toggleRecipe(candidate.id)
                    }
                    .font(.subheadline).textCase(nil)
                    .accessibilityLabel(candidate.allSelected ? "Deselect all \(candidate.title) ingredients" : "Select all \(candidate.title) ingredients")
                }
            }
        } footer: {
            if candidate.onListCount > 0 {
                Text("On list matches an unchecked item for this recipe. Quantities may differ. Matching ingredients start unselected. Select them to add more.")
            }
            if candidate.plannedOccurrences > 1 {
                Text("Planned more than once. This amount uses the largest serving count for one meal, not the total for the week.")
            }
        }
    }
}
