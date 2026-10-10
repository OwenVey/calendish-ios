import SwiftUI

/// Cook mode's ingredient checklist, shown beside the steps or in a sheet.
/// Serving scale comes from the recipe page, so the panel stays focused on ingredients.
struct CookIngredientPanel: View {
    let recipe: Recipe
    let stepIndex: Int
    let scale: Double
    @Binding var scope: CookIngredientScope
    @Binding var checked: Set<UUID>
    let focus: CookIngredientFocus?
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.cookingHaptics) private var haptics = true
    @AppStorage(MeasurementPreference.storageKey) private var units = MeasurementPreference.original

    private var visibleIngredients: [Ingredient] {
        guard scope == .currentStep else { return recipe.ingredients }
        guard recipe.steps.indices.contains(stepIndex) else { return [] }
        let mentioned = Set(IngredientParser.mentions(in: recipe.steps[stepIndex],
            ingredients: recipe.ingredients.map(\.text)).flatMap(\.ingredients))
        return recipe.ingredients.enumerated().compactMap { mentioned.contains($0.offset) ? $0.element : nil }
    }

    var body: some View {
        let ingredients = visibleIngredients
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Menu {
                    Picker("Ingredients", selection: $scope) {
                        ForEach(CookIngredientScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(scope.rawValue).font(.title2.weight(.semibold)).foregroundStyle(Color.primary)
                        Image(systemName: "chevron.down").font(.body.weight(.semibold)).foregroundStyle(CalendishStyle.accent)
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44, alignment: .leading)
                }
                .tint(Color.primary)
                .accessibilityHint("Show all ingredients or only those mentioned in the current step")
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Label("Hide ingredients", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("cook-ingredients-close")
                .tint(Color.primary)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if ingredients.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(scope == .currentStep ? "No matching ingredients" : "No ingredients listed")
                                    .font(.headline)
                                Text(scope == .currentStep ? "No matching ingredients found for this step. Choose All ingredients to see the full list." : "Follow the recipe’s instructions to get started.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                        }
                        ForEach(ingredients) { ingredient in
                            CookIngredientRow(ingredient: ingredient, line: ingredient.display(scale: scale, units: units),
                                              isChecked: checked.contains(ingredient.id),
                                              isFocused: focus?.ingredients.contains(ingredient.id) == true) {
                                toggle(ingredient.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                .onChange(of: focus?.id) { _, _ in scrollToFocus(using: scroll) }
                .onChange(of: scope) { _, _ in scrollToFocus(using: scroll) }
                .onAppear { scrollToFocus(using: scroll) }
            }
        }
        .sensoryFeedback(.selection, trigger: checked) { _, _ in haptics }
    }

    private func toggle(_ id: UUID) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }

    private func scrollToFocus(using scroll: ScrollViewProxy) {
        guard let ingredient = focus?.ingredients.first else { return }
        withAnimation(reduceMotion ? nil : .default) { scroll.scrollTo(ingredient, anchor: .center) }
    }
}
