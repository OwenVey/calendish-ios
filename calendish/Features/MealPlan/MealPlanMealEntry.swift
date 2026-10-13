import SwiftUI

/// A planned meal in a meal plan day: opens its saved recipe, drags to another day, and edits, shops for, or removes from its menu.
struct MealPlanMealEntry: View {
    let meal: PlannedMeal
    let edit: (PlannedMeal) -> Void
    let remove: (PlanRemoval) -> Void
    let addToGroceries: (PlannedMeal) -> Void
    @Environment(HouseholdStore.self) private var store

    var body: some View {
        NavigationLink(value: meal) {
            RecipeRow(recipe: meal.recipe, servings: meal.servings)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .draggable(PlannedMealDrag(entryID: meal.id)) {
            RecipeRow(recipe: meal.recipe, servings: meal.servings)
                .padding(10)
                .frame(width: 320, alignment: .leading)
                .background(CalendishStyle.surface, in: .rect(cornerRadius: 20, style: .continuous))
                // Drag previews render outside the view hierarchy, so they don't inherit the environment.
                .environment(store)
        }
        .calendishContextMenu {
            Button("Edit meal", systemImage: "pencil") { edit(meal) }
            Button("Add to groceries", systemImage: "basket") { addToGroceries(meal) }
            Button("Remove meal", systemImage: "trash", role: .destructive) { remove(PlanRemoval(meals: [meal])) }
        }
        .accessibilityAction(named: "Edit meal") { edit(meal) }
        .accessibilityAction(named: "Add to groceries") { addToGroceries(meal) }
        .accessibilityAction(named: "Remove meal") { remove(PlanRemoval(meals: [meal])) }
    }
}
