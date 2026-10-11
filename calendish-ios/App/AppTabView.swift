import SwiftUI

/// The app's four tabs, each with its own navigation stack.
struct AppTabView: View {
    @Binding var selection: AppTab
    var onResumeCooking: (CookTimer) -> Void = { _ in }
    @Environment(CookingTimers.self) private var timers

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
        .modifier(RunningTimersAccessoryModifier(isEnabled: !timers.timers.isEmpty, onResume: onResumeCooking))
    }
}

/// Shows running timers above the tab bar. iOS 26.0 uses an inset because its native accessory can't be hidden without replacing the tab hierarchy.
private struct RunningTimersAccessoryModifier: ViewModifier {
    let isEnabled: Bool
    let onResume: (CookTimer) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) { RunningTimersAccessory(onResume: onResume) }
        } else {
            // Keep the tab hierarchy stable when the first timer starts or the last ends.
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isEnabled {
                    RunningTimersAccessory(onResume: onResume)
                        .padding(.vertical, 12)
                        .background(.bar)
                }
            }
        }
    }
}
