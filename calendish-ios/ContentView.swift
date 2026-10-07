import SwiftUI
import GoogleSignIn

enum AppTab: Hashable {
    case recipes, plan, groceries, settings
}

struct ContentView: View {
    @State private var store: HouseholdStore
    @State private var selectedTab: AppTab = .recipes
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @Environment(\.scenePhase) private var scenePhase

    init(store: HouseholdStore = HouseholdStore()) {
        _store = State(initialValue: store)
    }

    var body: some View {
        Group {
            switch store.phase {
            case .loading: ProgressView()
            case .signedOut: SignInView()
            case .needsHousehold: HouseholdSetupView()
            case .ready: tabs
            }
        }
        .tint(CalendishStyle.accent)
        .environment(store)
        .preferredColorScheme(appearance.colorScheme)
        .task { await store.start() }
        .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        .onChange(of: scenePhase) { _, phase in
            // Catch up on anything missed while Realtime was disconnected in the background.
            if phase == .active, store.phase == .ready { Task { await store.refresh() } }
        }
        .alert("Couldn’t sync", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Recipes", systemImage: "book.closed", value: .recipes) {
                NavigationStack { RecipeBookView() }
            }
            Tab("Meal Plan", systemImage: "calendar", value: .plan) {
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

#Preview { ContentView(store: .preview()) }
