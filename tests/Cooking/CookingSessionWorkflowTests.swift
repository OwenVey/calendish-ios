import ActivityKit
import Foundation

/// Records Live Activity calls in place of ActivityKit.
@MainActor
private final class RecordedActivities: CookingActivities {
    var areEnabled = true
    private(set) var started: [UUID] = []
    private(set) var updates: [(session: UUID, step: Int)] = []
    private(set) var ended: [(session: UUID?, finished: Bool)] = []
    private(set) var live: Set<UUID> = []

    func isShowing(session: UUID) -> Bool { live.contains(session) }
    func start(_ attributes: CookingActivityAttributes, content: Content) throws {
        started.append(attributes.sessionID)
        live.insert(attributes.sessionID)
    }
    func update(session: UUID, to content: Content) async { updates.append((session, content.state.stepIndex)) }
    func showing() -> Set<String> { Set(live.map(\.uuidString)) }
    func end(_ activities: Set<String>, session: UUID?, finished: Bool) async {
        ended.append((session, finished))
        live = live.filter { !activities.contains($0.uuidString) || (session != nil && $0 != session) }
    }
}

/// Timer alerts that are always allowed and never reach the system.
@MainActor
private final class SilentAlerts: CookingTimerAlerts {
    func authorizeAlarms() async -> Bool { false }
    func scheduleAlarm(for timer: CookTimer) async throws { }
    func authorizeNotifications() async throws -> Bool { true }
    func scheduleNotification(for timer: CookTimer, withSound: Bool) async throws { }
    func withdraw(_ id: UUID) { }
    func playFinishedSound() { }
}

/// The cooking session through its interface, with its storage, timers, finished cooks, and Live Activity controlled.
/// Run inside the hands-free cooking harness.
@MainActor
enum CookingSessionWorkflowTests {
    private struct Fixture {
        let defaults: UserDefaults
        let activities = RecordedActivities()
        let finishedCooks: FinishedCooks
        let session: CookingSession

        init(defaults suite: String = "cooking-session-\(UUID().uuidString)", liveActivity: Bool = true) {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(liveActivity, forKey: PreferenceKey.liveActivity)
            finishedCooks = FinishedCooks(defaults: defaults)
            session = CookingSession(timers: CookingTimers(alerts: SilentAlerts(), defaults: defaults),
                finishedCooks: finishedCooks, defaults: defaults, activities: activities)
        }

        /// Another launch reading what this one saved.
        func relaunched() -> CookingSession {
            CookingSession(timers: CookingTimers(alerts: SilentAlerts(), defaults: defaults),
                finishedCooks: finishedCooks, defaults: defaults, activities: activities)
        }
    }

    private static let recipe = Recipe(title: "Session stew", summary: "", prepMinutes: 0, cookMinutes: 30, servings: 4, tags: [],
        symbol: "fork.knife", ingredients: [], steps: ["Chop the onions.", "Simmer for 20 minutes.", "Serve."])

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "Cooking session: \(message)", code: 1) }
    }
    private static func until(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "Cooking session timed out: \(message)", code: 1)
    }

    static func run() async throws {
        try await finishingFromTheLiveActivityRecordsACook()
        try await staleLiveActivityTapsDoNothing()
        try await closingWithTimersKeepsThePlace()
        try await sessionsSurviveRelaunchButNotAccountChanges()
        try await liveActivityFollowsThePreference()
        try await timerChangesUpdateTheLiveActivity()
    }

    private static func finishingFromTheLiveActivityRecordsACook() async throws {
        let fixture = Fixture()
        let account = UUID(), cooked = UUID()
        fixture.session.setAccount(account)
        fixture.session.begin(recipe: recipe, servings: 4, cookedRecipeID: cooked)
        guard let id = fixture.session.snapshot?.id else { throw NSError(domain: "Cooking session: begin opens a session", code: 1) }
        try expect(fixture.activities.started == [id], "beginning shows one Live Activity")
        for step in 0..<recipe.steps.count { await fixture.session.advance(sessionID: id.uuidString, from: step) }
        try expect(fixture.session.snapshot == nil, "advancing past the last step ends the session")
        try expect(fixture.finishedCooks.pending == [FinishedCook(recipeID: cooked, startedAt: .now, accountID: account)],
            "a finished cook waits to be recorded for the signed-in account")
        try expect(fixture.activities.ended.last.map { $0.session == id && $0.finished } == true, "the Live Activity shows the cook finished")
    }

    private static func staleLiveActivityTapsDoNothing() async throws {
        let fixture = Fixture()
        fixture.session.begin(recipe: recipe, servings: 4)
        let id = fixture.session.snapshot!.id
        await fixture.session.advance(sessionID: UUID().uuidString, from: 0)
        await fixture.session.advance(sessionID: id.uuidString, from: 1)
        try expect(fixture.session.stepIndex == 0, "taps from another session or an earlier step are ignored")
        await fixture.session.startTimer(sessionID: id.uuidString, at: 1)
        try expect(fixture.session.timers.timers.isEmpty, "a timer button for a step that isn't showing does nothing")
    }

    private static func closingWithTimersKeepsThePlace() async throws {
        let fixture = Fixture()
        fixture.session.begin(recipe: recipe, servings: 4)
        fixture.session.setStep(1)
        await fixture.session.startTimer(sessionID: fixture.session.snapshot!.id.uuidString, at: 1)
        try expect(fixture.session.timers.timers.count == 1, "the Live Activity starts the step's suggested timer")
        try expect(fixture.session.startCurrentStepTimer() == .alreadyRunning, "a step runs one timer at a time")
        fixture.session.end(keepingPlace: true)
        try expect(fixture.session.place(for: recipe.id)?.stepIndex == 1, "closing with a timer running remembers the step")
        fixture.session.begin(recipe: recipe, servings: 2)
        try expect(fixture.session.stepIndex == 1 && fixture.session.snapshot?.servings == 2 && fixture.session.paused == nil,
            "reopening resumes at the remembered step")

        fixture.session.timers.timers.forEach(fixture.session.timers.cancel)
        fixture.session.end(keepingPlace: true)
        try expect(fixture.session.place(for: recipe.id) == nil, "without timers, closing forgets the place")
    }

    private static func sessionsSurviveRelaunchButNotAccountChanges() async throws {
        let fixture = Fixture()
        let account = UUID()
        fixture.session.setAccount(account)
        fixture.session.begin(recipe: recipe, servings: 4)
        fixture.session.setStep(2)
        let relaunched = fixture.relaunched()
        try expect(relaunched.snapshot?.id == fixture.session.snapshot?.id && relaunched.stepIndex == 2, "an open session survives relaunch")
        relaunched.setAccount(account)
        try expect(relaunched.snapshot != nil, "signing in again as the same person keeps the session")
        relaunched.setAccount(UUID())
        try expect(relaunched.snapshot == nil && fixture.relaunched().snapshot == nil, "another account never sees the session")
    }

    private static func liveActivityFollowsThePreference() async throws {
        let off = Fixture(liveActivity: false)
        off.session.begin(recipe: recipe, servings: 4)
        try expect(off.activities.started.isEmpty, "no Live Activity when the setting is off")

        let denied = Fixture()
        denied.activities.areEnabled = false
        denied.session.begin(recipe: recipe, servings: 4)
        try expect(denied.activities.started.isEmpty && denied.session.activityWarning != nil, "explains when Live Activities aren't allowed")

        let on = Fixture()
        on.session.begin(recipe: recipe, servings: 4)
        on.session.begin(recipe: recipe, servings: 4)
        try expect(on.activities.started.count == 1, "reopening the same session reuses its Live Activity")
        on.defaults.set(false, forKey: PreferenceKey.liveActivity)
        on.session.begin(recipe: recipe, servings: 4)
        try await until("turning the setting off ends the showing activity") { on.activities.live.isEmpty }
    }

    private static func timerChangesUpdateTheLiveActivity() async throws {
        let fixture = Fixture()
        fixture.session.begin(recipe: recipe, servings: 4)
        fixture.session.setStep(1)
        let before = fixture.activities.updates.count
        _ = fixture.session.startCurrentStepTimer()
        try await until("a new timer updates the Live Activity") { fixture.activities.updates.count > before }
        fixture.session.timers.timers.forEach(fixture.session.timers.cancel)
        fixture.session.end()
    }
}
