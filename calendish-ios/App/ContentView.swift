import GoogleSignIn
import Supabase
import SwiftUI

struct ContentView: View {
    @State private var store: HouseholdStore
    @State private var timers = CookingTimers.shared
    @State private var resumedCooking: CookingSession.Snapshot?
    @State private var resumedChecked: Set<UUID> = []
    @State private var selectedTab: AppTab = .recipes
    @State private var recipePath = NavigationPath()
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
            case .ready: AppTabView(selection: $selectedTab, recipePath: $recipePath, onResumeCooking: resumeCooking)
            }
        }
        .animation(.easeOut(duration: 0.3), value: store.phase)
        .tint(CalendishStyle.accent)
        .environment(store)
        .environment(timers)
        .environment(\.openRecipe, openRecipe)
        .calendishAlert("Timer finished", isPresented: Binding(get: { !timers.finished.isEmpty && !timers.isCooking }, set: { if !$0, !timers.isCooking { timers.acknowledge() } })) {
            Button("Done") { }
        } message: {
            Text(timers.finished.map { "\($0.recipeTitle), step \($0.stepIndex + 1): \($0.durationText) timer finished." }.joined(separator: "\n\n"))
        }
        .fullScreenCover(item: $resumedCooking) { session in
            CookModeView(recipe: session.recipe, servings: session.servings, checked: $resumedChecked)
                .environment(store)
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
            } else if store.openInvite(url) { selectedTab = .settings }
            else if url.scheme == "calendish" { supabase.auth.handle(url) }
            else { GIDSignIn.sharedInstance.handle(url) }
        }
        .sheet(item: $store.inviteToReview) { invite in
            HouseholdMoveView(code: invite.code).environment(store)
        }
        .sheet(isPresented: $store.needsPasswordReset) { PasswordResetView().environment(store) }
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
                .environment(\.openRecipe, openRecipe)
                .onAppear { SharedInbox.remove(share.id) }
        }
        .calendishAlert(store.errorTitle, item: $store.errorMessage) { _ in
            Button("OK") { }
        } message: { Text($0) }
        .menuStyle(CalendishMenuStyle())
    }

    /// Reopens Cook Mode where the timer's recipe left off, or at the timer's step when that place is gone.
    private func resumeCooking(_ timer: CookTimer) {
        let session = CookingSession.shared
        if let place = session.place(for: timer.recipeID) {
            session.prepareResume(place)
            resumedCooking = place
        } else if let recipe = store.recipes.first(where: { $0.id == timer.recipeID }),
                  recipe.steps.indices.contains(timer.stepIndex) {
            let place = CookingSession.Snapshot(recipe: recipe, servings: recipe.servings, stepIndex: timer.stepIndex,
                cookedRecipeID: CookedHistory.recipeID(cooking: recipe, plannedMeal: nil, in: store.recipes))
            session.prepareResume(place)
            resumedCooking = place
        }
    }

    /// Shows the recipe on its own in the Recipes tab.
    private func openRecipe(_ recipe: Recipe) {
        selectedTab = .recipes
        recipePath = NavigationPath([recipe])
    }

    /// Recipes shared from other apps open in the Recipes tab, one at a time.
    private func openNextShare() {
        guard store.phase == .ready, sharedImport == nil, let share = SharedInbox.next() else { return }
        selectedTab = .recipes
        sharedImport = SharedImport(id: share.id, item: share.item)
    }
}

#Preview { ContentView(store: .preview()) }
