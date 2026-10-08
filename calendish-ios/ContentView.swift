import SwiftUI
import GoogleSignIn
import Supabase

enum AppTab: Hashable {
    case recipes, plan, groceries, settings
}

struct ContentView: View {
    @State private var store: HouseholdStore
    @State private var timers = CookingTimers.shared
    @State private var resumedCooking: CookingSession.Snapshot?
    @State private var resumedChecked: Set<UUID> = []
    @State private var selectedTab: AppTab = .recipes
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @Environment(\.scenePhase) private var scenePhase
    @State private var sharedImport: SharedImport?
    @State private var shareDrafts = RecipeImportDrafts()

    private struct SharedImport: Identifiable {
        let id: String
        let item: RecipeImport
    }

    init(store: HouseholdStore = HouseholdStore()) {
        _store = State(initialValue: store)
    }

    var body: some View {
        Group {
            switch store.phase {
            case .loading: LoadingView()
            case .signedOut: SignInView()
            case .onboarding: HouseholdSetupView()
            case .ready: tabs
            }
        }
        .animation(.easeOut(duration: 0.3), value: store.phase)
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
        .fullScreenCover(item: $resumedCooking) { session in
            CookModeView(recipe: session.recipe, servings: session.servings, checked: $resumedChecked)
                .environment(timers)
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await store.start() }
        .onOpenURL { url in
            if url.scheme == "calendish", url.host == "cooking" {
                if let session = CookingSession.shared.snapshot,
                   url.lastPathComponent == session.id.uuidString, !timers.isCooking {
                    resumedCooking = session
                }
            }
            else if store.openInvite(url) { selectedTab = .settings }
            else if url.scheme == "calendish" { supabase.auth.handle(url) }
            else { GIDSignIn.sharedInstance.handle(url) }
        }
        .sheet(item: Binding(get: { store.inviteToReview }, set: { store.inviteToReview = $0 })) { invite in
            HouseholdMoveView(code: invite.code).environment(store)
        }
        .sheet(isPresented: Binding(get: { store.needsPasswordReset }, set: { store.needsPasswordReset = $0 })) { PasswordResetView().environment(store) }
        .onChange(of: scenePhase) { _, phase in
            // Catch up on anything missed while Realtime was disconnected in the background.
            if phase == .active, store.phase == .ready { Task { await store.resumeSync() } }
            if phase == .active { openNextShare() }
        }
        .onChange(of: store.phase) { _, _ in openNextShare() }
        .sheet(item: $sharedImport, onDismiss: openNextShare) { share in
            // Sheets attached out here sit outside the `.environment` modifiers above.
            RecipeImportView(start: .content(share.item), drafts: $shareDrafts)
                .environment(store)
                .onAppear { SharedInbox.remove(share.id) }
        }
        .alert("Couldn’t sync", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .menuStyle(CalendishMenuStyle())
    }

    /// Recipes shared from other apps open in the Recipes tab, one at a time.
    private func openNextShare() {
        guard store.phase == .ready, sharedImport == nil, let share = SharedInbox.next() else { return }
        selectedTab = .recipes
        sharedImport = SharedImport(id: share.id, item: share.item)
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
            .badge(store.groceries.count { !$0.isComplete })
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
    }
}

/// Matches the launch screen (a plain LaunchBackground) so there's no flash, only showing a spinner if loading runs long.
private struct LoadingView: View {
    @State private var showSpinner = false
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            if showSpinner { ProgressView() }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            showSpinner = true
        }
    }
}

#Preview { ContentView(store: .preview()) }
