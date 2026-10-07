import SwiftUI
import GoogleSignIn
import Supabase

enum AppTab: Hashable {
    case recipes, plan, groceries, settings
}

struct ContentView: View {
    @State private var store: HouseholdStore
    @State private var timers = CookingTimers()
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
        .environment(timers)
        .task(id: timers.timers.map(\.end)) { await timers.waitForNextTimer() }
        .alert("Timer Done", isPresented: Binding(get: { !timers.finished.isEmpty && !timers.isCooking }, set: { if !$0 && !timers.isCooking { timers.acknowledge() } })) {
            Button("Done") { }
        } message: {
            Text(timers.finished.map { "\($0.recipeTitle), step \($0.stepIndex + 1): your \($0.durationText) timer is up." }.joined(separator: "\n\n"))
        }
        .safeAreaInset(edge: .bottom) {
            if !timers.timers.isEmpty {
                Menu {
                    ForEach(timers.timers) { timer in
                        Button("Cancel \(timer.recipeTitle), Step \(timer.stepIndex + 1)", role: .destructive) { timers.cancel(timer) }
                    }
                } label: {
                    Label("\(timers.timers.count) \(timers.timers.count == 1 ? "Timer" : "Timers") Running", systemImage: "timer").frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity).background(CalendishStyle.surface)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await store.start() }
        .onOpenURL { url in
            if url.scheme == "calendish" { supabase.auth.handle(url) }
            else { GIDSignIn.sharedInstance.handle(url) }
        }
        .sheet(isPresented: Binding(get: { store.needsPasswordReset }, set: { store.needsPasswordReset = $0 })) { PasswordResetView() }
        .onChange(of: scenePhase) { _, phase in
            // Catch up on anything missed while Realtime was disconnected in the background.
            if phase == .active, store.phase == .ready { Task { await store.refresh() } }
        }
        .alert("Couldn’t sync", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .menuStyle(CalendishMenuStyle())
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
