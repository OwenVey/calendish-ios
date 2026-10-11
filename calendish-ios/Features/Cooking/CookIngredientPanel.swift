import SwiftUI

/// Cook mode's ingredient checklist, shown beside the steps or in a sheet.
/// Serving scale comes from the recipe page, so the panel stays focused on ingredients.
/// In the sheet, the panel never closes: it collapses to its header so a thumb can drag it back up.
struct CookIngredientPanel: View {
    let recipe: Recipe
    let stepIndex: Int
    let scale: Double
    @Binding var scope: CookIngredientScope
    @Binding var checked: Set<UUID>
    let focus: CookIngredientFocus?
    /// The sheet's state, or nil beside the steps, where the panel closes instead of collapsing.
    var isCollapsed: Bool?
    let onClose: () -> Void
    var onExpand: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                Text("Ingredients")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Menu {
                    Picker("Ingredients", selection: $scope) {
                        ForEach(CookIngredientScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(scope.shortTitle).lineLimit(1)
                        Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .tint(Color.primary)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .accessibilityLabel("Ingredients shown")
                .accessibilityValue(scope.rawValue)
                .accessibilityHint("Show all ingredients or only those mentioned in the current step")
                headerButton
                    .labelStyle(.iconOnly)
                    .tint(Color.primary)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
            }
            .padding(.leading, 20)
            // Collapsed, the header is all that shows: center it in the floating sheet,
            // with the expand button's side margin matching its top and bottom.
            .padding(.trailing, isCollapsed == true ? 10 : 20)
            .padding(.top, isCollapsed == true ? 12 : 16)
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
        .hapticFeedback(.selection, trigger: checked)
    }

    @ViewBuilder private var headerButton: some View {
        switch isCollapsed {
        case nil:
            Button("Hide ingredients", systemImage: "xmark", role: .close, action: onClose)
                .accessibilityIdentifier("cook-ingredients-close")
        case false?:
            Button("Collapse ingredients", systemImage: "chevron.down", action: onClose)
                .accessibilityIdentifier("cook-ingredients-close")
        case true?:
            Button("Expand ingredients", systemImage: "chevron.up", action: onExpand)
                .accessibilityIdentifier("cook-ingredients-expand")
        }
    }

    private func toggle(_ id: UUID) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }

    private func scrollToFocus(using scroll: ScrollViewProxy) {
        guard let ingredient = focus?.ingredients.first else { return }
        withAnimation(reduceMotion ? nil : .default) { scroll.scrollTo(ingredient, anchor: .center) }
    }
}
