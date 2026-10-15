import SwiftUI

@MainActor
private final class OperationGate {
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { entered = true; continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@main
struct HouseholdWorkflowApp: App {
    @State private var result = "Running workflow tests…"
    @State private var uiStore = HouseholdStore.preview()
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--ui-setup") {
                HouseholdSetupView().environment(uiStore)
            } else if ProcessInfo.processInfo.arguments.contains("--ui-leave") {
                HouseholdMoveView(leaving: true).environment(uiStore)
            } else if ProcessInfo.processInfo.arguments.contains("--ui-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-invite")
                || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-notification") }) {
                ContentView(store: uiStore).onAppear {
                    if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-notification") }) {
                        openNotificationFixture(argument)
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-invite") {
                        _ = uiStore.openInvite(URL(string: "calendish://join/VALID123")!)
                    }
                }
            } else {
            Text(result).padding().task {
                do { try await run(); result = "PASS" }
                catch { result = "FAIL: \(error)" }
                try? Data(result.utf8).write(to: URL.documentsDirectory.appending(path: "result.txt"))
            }
            }
        }
    }
    private func openNotificationFixture(_ argument: String) {
        guard let user = uiStore.userID, let home = uiStore.household?.id, let recipe = uiStore.recipes.first else { return }
        HouseholdNotifications.shared.pendingAlert = HouseholdAlert(userInfo: [
            "type": argument == "--ui-notification-groceries" ? "household_groceries" : "household_recipe", "household_id": home.uuidString,
            "recipient_id": (argument == "--ui-notification-other-account" ? UUID() : user).uuidString,
            "recipe_id": (argument == "--ui-notification-missing" ? UUID() : recipe.id).uuidString,
        ])
    }
    private func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }
    private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now >= deadline { throw NSError(domain: "Timed out waiting for workflow state", code: 1) }
            await Task.yield()
        }
    }
    private func run() async throws {
        try HouseholdNotificationTests.run()
        try await SupabaseHouseholdBackendContractTests.run()
        try await AutoPlanWorkflowTests.run()
        UserDefaults.standard.removeObject(forKey: "pendingHouseholdInvite")
        defer { UserDefaults.standard.removeObject(forKey: "pendingHouseholdInvite") }
        let backend = InMemoryHouseholdBackend()
        let defaults = UserDefaults(suiteName: "finished-cook-workflow-\(UUID().uuidString)")!
        let finishedCooks = FinishedCooks(defaults: defaults)
        let store = HouseholdStore(backend: backend, finishedCooks: finishedCooks)
        let session = Task { await store.start() }
        defer { session.cancel() }
        try await until { store.phase == .signedOut }
        try await store.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { store.phase == .onboarding }
        let entryGate = OperationGate()
        backend.beforeSnapshot = { _ in await entryGate.wait() }
        let entering = Task { try await store.startHousehold(memberName: "Fixture") }
        try await until { entryGate.entered }
        backend.beforeSnapshot = nil
        await store.signOut()
        try await until { store.phase == .signedOut }
        entryGate.release()
        do { try await entering.value; throw NSError(domain: "Stale entry must cancel", code: 1) }
        catch is CancellationError { }
        try expect(store.phase == .signedOut && store.household == nil, "Sign-out during onboarding reload cannot resurrect ready state")

        let home = try await backend.currentHousehold(user: backend.identity.id)!
        var original = SampleRecipes.all[0]
        original.title = "Original recipe"; original.steps = ["Cook rice."]
        original.owner = .person(backend.identity.id, shared: true)
        backend.seed(HouseholdSnapshot(household: Household(id: home.id, name: home.name, inviteCode: home.inviteCode),
            members: [HouseholdMember(userID: backend.identity.id, displayName: "Fixture", role: "owner")], recipes: [original]))
        let destination = Household(id: UUID(), name: "Partner household", inviteCode: "VALID123")
        var destinationRecipe = SampleRecipes.all[1]
        destinationRecipe.title = "Destination recipe"; destinationRecipe.owner = .household
        backend.seed(HouseholdSnapshot(household: destination,
            members: [HouseholdMember(userID: UUID(), displayName: "Partner", role: "owner")], recipes: [destinationRecipe]))
        try await store.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { store.phase == .ready }
        try expect(store.recipes.first?.title == "Original recipe", "Onboarding reloads the household and recipes")
        store.saveMeal(date: .now, recipe: original, servings: 6)
        await store.waitForSaves()
        var edited = original; edited.steps = ["Different instructions."]
        store.saveRecipe(edited)
        await store.waitForSaves()
        try expect(store.meals.first?.recipe.steps == ["Cook rice."] && store.meals.first?.servings == 6,
            "Recipe edits leave saved meal content and servings unchanged after reload")
        let savedMeal = store.meals[0]
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: savedMeal.date)!
        store.saveMeal(date: tomorrow, recipe: savedMeal.recipe, servings: 3, editing: savedMeal, keepVersion: true)
        await store.waitForSaves()
        try expect(store.meals.first?.id == savedMeal.id && Calendar.current.isDate(store.meals.first!.date, inSameDayAs: tomorrow)
            && store.meals.first?.recipe.steps == ["Cook rice."], "Moving a meal keeps its identity and saved version")

        // A new broadcast cancels the previous HTTP refresh. URLSession reports this
        // as URLError.cancelled, rather than Swift's CancellationError.
        let cancelledRefresh = OperationGate()
        backend.beforeSnapshot = { _ in
            await cancelledRefresh.wait()
            while !Task.isCancelled { await Task.yield() }
            throw URLError(.cancelled)
        }
        backend.emit(.household, household: home.id)
        try await until { cancelledRefresh.entered }
        backend.beforeSnapshot = nil
        backend.emit(.household, household: home.id)
        cancelledRefresh.release()
        // Await the canceled refresh's error handler and the replacement debounce.
        try await Task.sleep(for: .milliseconds(650))
        try expect(store.errorMessage == nil,
            "Superseded Realtime refresh must not show Couldn't update household data")

        // Real connection failures still surface, with metadata that survives relaunch.
        let privatePayload = "fixture-private-response-content"
        backend.emit(.failure(NSError(domain: "RealtimeFixture", code: 7,
            userInfo: [NSLocalizedDescriptionKey: privatePayload])), household: home.id)
        try await until { store.errorMessage != nil }
        try expect(store.errorTitle == "Couldn’t update household data" &&
            store.errorMessage == "Reopen Calendish to try again.", "Real Realtime failures retain the alert")
        let diagnosticData = try Data(contentsOf: HouseholdSyncDiagnostics.fileURL)
        let diagnostics = try JSONDecoder().decode([[String: String]].self, from: diagnosticData)
        try expect(diagnostics.last?["source"] == "realtime-subscription" && diagnostics.last?["code"] == "7",
            "Record the actual failing source and code")
        try expect(!String(decoding: diagnosticData, as: UTF8.self).contains(privatePayload),
            "Diagnostics must not retain private error payloads")
        store.errorMessage = nil

        // A snapshot spanning a write acknowledgment must not roll the optimistic edit back.
        let readGate = OperationGate()
        backend.beforeSnapshot = { _ in await readGate.wait() }
        let oldRead = Task { await store.refresh() }
        try await until { readGate.entered }
        backend.beforeSnapshot = nil
        store.renameHousehold(to: "Updated home")
        await store.waitForSaves()
        readGate.release(); await oldRead.value
        try expect(store.household?.name == "Updated home", "Reject reads spanning a completed write")
        backend.beforeWrite = { _ in throw URLError(.notConnectedToInternet) }
        store.renameHousehold(to: "Unsaved name")
        await store.waitForSaves()
        try expect(store.household?.name == "Updated home" && store.errorMessage != nil, "Failed writes show an error and restore authoritative state")
        backend.beforeWrite = nil; store.errorMessage = nil
        store.renameHousehold(to: "First edit"); store.renameHousehold(to: "Last edit")
        await store.waitForSaves()
        try expect(store.household?.name == "Last edit", "Rapid writes retain their order through reload")
        store.saveReview(of: original.id, rating: 9, note: "  Nice  ")
        store.markCooked(original.id); store.markCooked(original.id)
        await store.waitForSaves()
        try expect(store.myReview(of: original.id)?.rating == 5 && store.myReview(of: original.id)?.note == "Nice" && store.cooks.count == 1,
            "Review normalization and cooked-day deduplication survive reload")
        // Exercise the complete durable handoff, not just a callback or a manual marked cook.
        let finishedDay = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let finishedCook = FinishedCook(recipeID: original.id, startedAt: finishedDay, accountID: backend.identity.id)
        backend.beforeWrite = { _ in throw URLError(.notConnectedToInternet) }
        finishedCooks.add(finishedCook)
        await store.waitForSaves()
        try expect(FinishedCooks(defaults: defaults).pending == [finishedCook], "Failed household write retains durable finished cook across relaunch")
        try expect(!store.cooks.contains { Calendar.current.isDate($0.date, inSameDayAs: finishedDay) }, "Failed completion removes optimistic marked cook")
        backend.beforeWrite = nil
        await store.resumeSync()
        await store.waitForSaves()
        try expect(finishedCooks.pending.isEmpty && store.cooks.filter { Calendar.current.isDate($0.date, inSameDayAs: finishedDay) }.count == 1,
            "Resume retries and acknowledges exactly one marked cook")
        finishedCooks.add(finishedCook)
        await store.waitForSaves()
        try expect(finishedCooks.pending.isEmpty && store.cooks.filter { Calendar.current.isDate($0.date, inSameDayAs: finishedDay) }.count == 1,
            "Already persisted completion is idempotently acknowledged")

        let completionGate = OperationGate()
        backend.beforeWrite = { _ in await completionGate.wait() }
        let interruptedCook = FinishedCook(recipeID: original.id, startedAt: Calendar.current.date(byAdding: .day, value: -3, to: .now)!, accountID: backend.identity.id)
        finishedCooks.add(interruptedCook)
        try await until { completionGate.entered }
        try expect(finishedCooks.pending == [interruptedCook], "Pending cook stays durable while write is in flight")
        await store.signOut()
        try await until { store.phase == .signedOut }
        completionGate.release()
        backend.beforeWrite = nil
        try await store.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { store.phase == .ready }
        await store.waitForSaves()
        try expect(finishedCooks.pending.isEmpty && store.cooks.filter { Calendar.current.isDate($0.date, inSameDayAs: interruptedCook.day) }.count == 1,
            "Interrupted completion survives account reset and is replayed without duplicates")

        store.saveReview(of: original.id, rating: nil, note: "")
        await store.waitForSaves()
        try expect(store.myReview(of: original.id) == nil, "Clearing a review deletes it")

        let preview = try await store.previewMove(code: "VALID123")
        do {
            try await store.joinHousehold(code: "INVALID", confirmed: preview, saveHouseholdRecipes: false)
            throw NSError(domain: "Invalid invitation unexpectedly succeeded", code: 1)
        } catch is HouseholdMoveRejected { }
        try expect(store.household?.id == home.id && !store.meals.isEmpty, "Rejected move keeps membership and meals")
        let formerGate = OperationGate()
        backend.beforeSnapshot = { _ in await formerGate.wait() }
        let formerRead = Task { await store.refresh() }
        try await until { formerGate.entered }
        backend.beforeSnapshot = nil
        backend.afterMove = { throw URLError(.networkConnectionLost) }
        try await store.joinHousehold(code: "VALID123", confirmed: preview, saveHouseholdRecipes: false)
        try expect(store.household?.id == destination.id && store.recipes.first?.title == "Destination recipe",
            "Lost move response recovers from authoritative membership")
        formerGate.release(); await formerRead.value
        try expect(store.recipes.first?.title == "Destination recipe" && store.meals.isEmpty, "Late former-household reload cannot republish old content")
        backend.afterMove = nil

        // Typed realtime events use the same reload and membership-following paths as production.
        try await backend.write(.renameHousehold(destination.id, "Changed elsewhere"))
        backend.emit(.household, household: destination.id)
        try await until { store.household?.name == "Changed elsewhere" }
        let leaving = try await backend.previewMove(code: nil)
        let moved = try await backend.move(code: nil, saveRecipes: false, expected: leaving.currentHouseholdID)
        backend.emit(.membership, household: destination.id)
        try await until { store.household?.id == moved.household.id && store.phase == .ready }
        try expect(store.meals.isEmpty, "Remote membership change opens the new household")

        let copyGate = OperationGate()
        backend.beforeCopy = { await copyGate.wait() }
        let copy = Task { try await store.saveCopy(of: store.recipes[0]) }
        try await until { copyGate.entered }
        await store.signOut()
        try await until { store.phase == .signedOut }
        copyGate.release()
        do { _ = try await copy.value; throw NSError(domain: "Stale copy must cancel", code: 1) }
        catch is CancellationError { }
        try expect(store.recipes.isEmpty && store.household == nil, "Late copy cannot repopulate a signed-out account")
        try expect(store.openInvite(URL(string: "calendish://join/VALID123")!), "Join links are recognized while signed out")
        let reopened = HouseholdStore(backend: backend)
        try expect(reopened.pendingInvite == "VALID123", "Invitations survive a new store instance")
        session.cancel()
        let reopenedSession = Task { await reopened.start() }
        defer { reopenedSession.cancel() }
        try await until { reopened.phase == .signedOut }
        try await reopened.signIn(email: "fixture@example.com", password: "fixture-password")
        try await until { reopened.phase == .ready }
        try expect(reopened.inviteToReview?.code == "VALID123" && reopened.pendingInvite == nil,
            "Authentication continues the pending invitation as a review without moving membership")

        let previewStore = HouseholdStore.preview()
        let previewInvitation = try await previewStore.previewMove(code: "VALID123")
        try expect(previewInvitation.destination?.name == "Sam’s household", "Preview invitations resolve through seeded adapter data")
        previewStore.renameHousehold(to: "Preview edit")
        await previewStore.waitForSaves()
        await previewStore.refresh()
        try expect(previewStore.household?.name == "Preview edit", "Previews use the real write and reload path")
    }
}
