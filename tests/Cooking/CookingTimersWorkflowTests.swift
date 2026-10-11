import SwiftUI

/// A controlled system-alert boundary: tests choose what the person allowed, hold a scheduling
/// request mid-flight, and observe which alerts are pending. Cooking timers run unchanged.
@MainActor
private final class ControlledAlerts: CookingTimerAlerts {
    var alarmsAllowed = false
    var notificationsAllowed = true
    /// Holds the next notification request until `release()`, like a slow system response.
    var holdsNextNotification = false
    private(set) var alarms: [UUID: Date] = [:]
    private(set) var notifications: [UUID: Date] = [:]
    private(set) var sounds = 0
    private var held: CheckedContinuation<Void, Never>?
    var isHolding: Bool { held != nil }

    func authorizeAlarms() async -> Bool { alarmsAllowed }
    func scheduleAlarm(for timer: CookTimer) async throws { alarms[timer.id] = timer.end }
    func authorizeNotifications() async throws -> Bool { notificationsAllowed }
    func scheduleNotification(for timer: CookTimer, withSound: Bool) async throws {
        if holdsNextNotification {
            holdsNextNotification = false
            await withCheckedContinuation { held = $0 }
        }
        notifications[timer.id] = timer.end
    }
    func withdraw(_ id: UUID) {
        alarms[id] = nil
        notifications[id] = nil
    }
    func playFinishedSound() { sounds += 1 }

    func release() { held?.resume(); held = nil }
}

@main
struct CookingTimersWorkflowApp: App {
    @State private var result = "Running cooking timer tests…"
    var body: some Scene {
        WindowGroup {
            Text(result).padding().task {
                do { try await run(); result = "PASS" }
                catch { result = "FAIL: \(error)" }
                try? Data(result.utf8).write(to: URL.documentsDirectory.appending(path: "result.txt"))
            }
        }
    }

    private func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }
    private func until(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "Timed out: \(message)", code: 1)
    }

    private let recipe = Recipe(title: "Timer bread", summary: "", prepMinutes: 0, cookMinutes: 30, servings: 4, tags: [],
                                symbol: "fork.knife", ingredients: [], steps: ["Proof for 1 hour.", "Bake for 30 minutes."])

    /// Fresh timers with nothing saved, alerting through `style`.
    private func timers(_ alerts: ControlledAlerts, style: TimerAlert = .notification, onChange: @escaping () -> Void = {}) -> CookingTimers {
        UserDefaults.standard.set(style.rawValue, forKey: PreferenceKey.timerAlert)
        let defaults = UserDefaults(suiteName: "cooking-timers-workflow")!
        defaults.removePersistentDomain(forName: "cooking-timers-workflow")
        return CookingTimers(alerts: alerts, defaults: defaults, onChange: onChange)
    }

    private func run() async throws {
        let workflows: [(String, () async throws -> Void)] = [
            ("scheduling", scheduling),
            ("extensionDuringScheduling", extensionDuringScheduling),
            ("pauseDuringScheduling", pauseDuringScheduling),
            ("pausedExtension", pausedExtension),
            ("alarmFallback", alarmFallback),
            ("notificationsOff", notificationsOff),
            ("expiration", expiration),
            ("alarmExpiration", alarmExpiration),
            ("restoredExpiration", restoredExpiration)
        ]
        for (name, workflow) in workflows {
            do { try await workflow() }
            catch { throw NSError(domain: "\(name): \((error as NSError).domain)", code: 1) }
        }
    }

    private func scheduling() async throws {
        let alerts = ControlledAlerts()
        var changes = 0
        let timers = timers(alerts) { changes += 1 }
        timers.start(recipe: recipe, stepIndex: 1, duration: 1800)
        try expect(changes == 1, "Starting a timer reports the change")
        await timers.alertsScheduled()
        let timer = timers.timers[0]
        try expect(alerts.notifications == [timer.id: timer.end] && timers.notificationWarning == nil,
            "A started timer has a notification for its end")
        timers.cancel(timer)
        try expect(timers.timers.isEmpty && alerts.notifications.isEmpty && changes == 2, "Cancelling withdraws the alert")
    }

    private func extensionDuringScheduling() async throws {
        let alerts = ControlledAlerts()
        alerts.holdsNextNotification = true
        let timers = timers(alerts)
        timers.start(recipe: recipe, stepIndex: 1, duration: 1800)
        try await until("the first request is in flight") { alerts.isHolding }
        timers.addMinute(to: timers.timers[0])
        alerts.release()
        await timers.alertsScheduled()
        let timer = timers.timers[0]
        try expect(timer.duration == 1860, "The extension lengthens the timer")
        try expect(alerts.notifications == [timer.id: timer.end],
            "A slow request for the old end can't outlive the extension's alert")
    }

    private func pauseDuringScheduling() async throws {
        let alerts = ControlledAlerts()
        alerts.holdsNextNotification = true
        let timers = timers(alerts)
        timers.start(recipe: recipe, stepIndex: 1, duration: 1800)
        try await until("the first request is in flight") { alerts.isHolding }
        timers.pause(timers.timers[0])
        alerts.release()
        await timers.alertsScheduled()
        try expect(timers.timers[0].isPaused && alerts.notifications.isEmpty, "A paused timer never keeps a pending alert")
        timers.resume(timers.timers[0])
        await timers.alertsScheduled()
        let timer = timers.timers[0]
        try expect(alerts.notifications == [timer.id: timer.end], "Resuming schedules the alert for the new end")
    }

    private func pausedExtension() async throws {
        let alerts = ControlledAlerts()
        let timers = timers(alerts)
        timers.start(recipe: recipe, stepIndex: 0, duration: 120)
        timers.pause(timers.timers[0])
        let remaining = timers.timers[0].pausedRemaining ?? 0
        timers.addMinute(to: timers.timers[0])
        await timers.alertsScheduled()
        try expect(timers.timers[0].pausedRemaining == remaining + 60 && alerts.notifications.isEmpty,
            "Extending a paused timer adds time left without scheduling an alert")
    }

    private func alarmFallback() async throws {
        let alerts = ControlledAlerts()
        let timers = timers(alerts, style: .alarm)
        timers.start(recipe: recipe, stepIndex: 0, duration: 3600)
        await timers.alertsScheduled()
        let timer = timers.timers[0]
        try expect(alerts.alarms.isEmpty && alerts.notifications == [timer.id: timer.end] && timer.usesAlarm == nil,
            "Without alarm access, a notification takes over")
        timers.cancel(timer)

        alerts.alarmsAllowed = true
        timers.start(recipe: recipe, stepIndex: 0, duration: 3600)
        await timers.alertsScheduled()
        let ringing = timers.timers[0]
        try expect(alerts.alarms == [ringing.id: ringing.end] && alerts.notifications.isEmpty && ringing.usesAlarm == true,
            "With alarm access, the alarm is the whole alert")
        timers.pause(ringing)
        await timers.alertsScheduled()
        try expect(alerts.alarms.isEmpty && timers.timers[0].usesAlarm == nil, "Pausing withdraws the alarm")
    }

    private func notificationsOff() async throws {
        let alerts = ControlledAlerts()
        alerts.notificationsAllowed = false
        let timers = timers(alerts)
        timers.start(recipe: recipe, stepIndex: 0, duration: 3600)
        await timers.alertsScheduled()
        try expect(timers.notificationWarning != nil && alerts.notifications.isEmpty, "Denied notifications are explained")
        alerts.notificationsAllowed = true
        timers.addMinute(to: timers.timers[0])
        await timers.alertsScheduled()
        try expect(timers.notificationWarning == nil, "The warning clears once notifications are allowed")
    }

    private func expiration() async throws {
        let alerts = ControlledAlerts()
        let timers = timers(alerts)
        timers.start(recipe: recipe, stepIndex: 0, duration: 1)
        timers.start(recipe: recipe, stepIndex: 1, duration: 1)
        timers.pause(timers.timers[0])
        try await until("the running timer finishes") { timers.finished.count == 1 }
        try expect(timers.finished[0].stepIndex == 1 && alerts.sounds == 1, "The running timer finishes in the app with a sound")
        try expect(timers.timers.map(\.stepIndex) == [0], "A paused timer doesn't finish")
        timers.acknowledge()
        timers.resume(timers.timers[0])
        try await until("the resumed timer finishes") { timers.finished.count == 1 }
        try expect(timers.timers.isEmpty, "Resuming lets the timer finish")
        timers.acknowledge()

        UserDefaults.standard.set(TimerAlert.silent.rawValue, forKey: PreferenceKey.timerAlert)
        timers.start(recipe: recipe, stepIndex: 0, duration: 1)
        try await until("the silent timer finishes") { timers.finished.count == 1 }
        try expect(alerts.sounds == 2, "Silent timers finish without a sound")
    }

    private func alarmExpiration() async throws {
        let alerts = ControlledAlerts()
        alerts.alarmsAllowed = true
        let timers = timers(alerts, style: .alarm)
        timers.start(recipe: recipe, stepIndex: 0, duration: 1)
        await timers.alertsScheduled()
        try expect(timers.timers.first?.usesAlarm == true, "The timer rings through an alarm")
        try await until("the alarm timer ends") { timers.timers.isEmpty }
        try await Task.sleep(for: .milliseconds(50))
        try expect(timers.finished.isEmpty && alerts.sounds == 0, "An alarm isn't repeated by an in-app alert")
    }

    private func restoredExpiration() async throws {
        let alerts = ControlledAlerts()
        let earlier = timers(alerts)
        earlier.start(recipe: recipe, stepIndex: 0, duration: 1)
        let defaults = UserDefaults(suiteName: "cooking-timers-workflow")!
        let restored = CookingTimers(alerts: alerts, defaults: defaults)
        try expect(restored.timers.count == 1, "Timers survive relaunch")
        try await until("a restored timer finishes") { restored.finished.count == 1 }
    }
}
