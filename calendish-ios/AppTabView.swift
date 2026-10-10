import SwiftUI

/// The app's four tabs, each with its own navigation stack.
struct AppTabView: View {
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Recipes", systemImage: "book.closed", value: .recipes) {
                NavigationStack { RecipeBookView() }
            }
            Tab("Meal plan", systemImage: "calendar", value: .plan) {
                NavigationStack { MealPlanView() }
            }
            Tab("Groceries", systemImage: "basket", value: .groceries) {
                NavigationStack { GroceryListView() }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
    }
}
