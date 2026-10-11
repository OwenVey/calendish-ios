import Observation
import SwiftUI

/// End dates persist independently of cooking screens; system alarms or notifications cover background expiration.
/// Timers finish themselves while Calendish is open, and keep their system alerts in step with every change.
@Observable
final class CookingTimers {
    static let shared = CookingTimers(onChange: { CookingSession.shared.refresh() })
    private(set) var timers: [CookTimer] = []
    var finished: [CookTimer] = []
    var isCooking = false
    var notificationWarning: String?
    @ObservationIgnored private var scheduling: Task<Void, Never>?
    @ObservationIgnored private var expiration: Task<Void, Never>?
    @ObservationIgnored private let alerts: CookingTimerAlerts
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let onChange: () -> Void
    private let storageKey = "activeCookingTimers"

    /// - Parameter onChange: Called after every change to the running timers, such as to update a Live Activity.
    init(alerts: CookingTimerAlerts = SystemCookingTimerAlerts(), defaults: UserDefaults = .standard, onChange: @escaping () -> Void = { }) {
        self.alerts = alerts
        self.defaults = defaults
        self.onChange = onChange
        if let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode([CookTimer].self, from: data) { timers = saved }
        watchNextExpiration()
    }
    private func changed() {
        defaults.set(try? JSONEncoder().encode(timers), forKey: storageKey)
        watchNextExpiration()
        onChange()
    }
    func start(recipe: Recipe, stepIndex: Int, duration: TimeInterval) {
        guard duration > 0 else { return }
        let timer = CookTimer(recipe: recipe, stepIndex: stepIndex, duration: duration)
        timers.append(timer); changed()
        reschedule(timer)
    }
    func pause(_ timer: CookTimer) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }), !timers[index].isPaused else { return }
        timers[index].pausedRemaining = max(1, timers[index].end.timeIntervalSinceNow)
        timers[index].usesAlarm = nil
        changed()
        reschedule(timers[index])
    }
    func resume(_ timer: CookTimer) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }), let remaining = timers[index].pausedRemaining else { return }
        timers[index].pausedRemaining = nil
        timers[index].end = .now.addingTimeInterval(remaining)
        changed()
        reschedule(timers[index])
    }
    func addMinute(to timer: CookTimer) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }) else { return }
        timers[index].duration += 60
        if let remaining = timers[index].pausedRemaining {
            timers[index].pausedRemaining = remaining + 60
            changed()
        } else {
            timers[index].end.addTimeInterval(60)
            changed()
            reschedule(timers[index])
        }
    }
    func acknowledge() { finished.removeAll() }
    func cancel(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }; changed()
        alerts.withdraw(timer.id)
    }

    /// Returns once every timer change made so far has its system alert in place, or withdrawn.
    /// Live Activity buttons wait for this so the system can't suspend Calendish before the alert exists.
    func alertsScheduled() async { await scheduling?.value }

    /// Replaces the timer's pending alert with one for its current end, or none while paused.
    /// Runs after any earlier scheduling, so a slow request can't land after a newer one.
    private func reschedule(_ timer: CookTimer) {
        let previous = scheduling
        scheduling = Task {
            await previous?.value
            alerts.withdraw(timer.id)
            guard isCurrent(timer) else { return }
            let alert = TimerAlert.current
            if alert == .alarm, await scheduleAlarm(for: timer) { return }
            do {
                guard try await alerts.authorizeNotifications() else {
                    notificationWarning = "Notifications are off. Keep Calendish open to see timer alerts, or allow notifications in Settings."
                    return
                }
                notificationWarning = nil
                guard isCurrent(timer) else { return }
                try await alerts.scheduleNotification(for: timer, withSound: alert != .silent)
                if !isCurrent(timer) { alerts.withdraw(timer.id) }
            } catch { notificationWarning = "Couldn’t schedule a timer notification. Keep Calendish open for the alert." }
        }
    }
    /// Whether the timer is still running and still ends when it did when scheduling began.
    private func isCurrent(_ timer: CookTimer) -> Bool {
        timers.contains { $0.id == timer.id && $0.deadline == timer.end } && timer.end > .now
    }
    /// Schedules a system alarm for the timer's end. Returns false, so a notification takes over,
    /// when alarms aren't allowed or scheduling fails.
    private func scheduleAlarm(for timer: CookTimer) async -> Bool {
        guard await alerts.authorizeAlarms(), isCurrent(timer) else { return false }
        do { try await alerts.scheduleAlarm(for: timer) } catch { return false }
        guard isCurrent(timer), let index = timers.firstIndex(where: { $0.id == timer.id }) else {
            alerts.withdraw(timer.id)
            return true
        }
        timers[index].usesAlarm = true; changed()
        notificationWarning = nil
        return true
    }

    /// Waits for the running timer that ends soonest, replacing any earlier wait.
    private func watchNextExpiration() {
        expiration?.cancel()
        guard let next = timers.filter({ !$0.isPaused }).min(by: { $0.end < $1.end }) else { expiration = nil; return }
        expiration = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, next.end.timeIntervalSinceNow))) } catch { return }
            self?.expire(next)
        }
    }
    /// Finishes a timer that reached its end. A system alarm is the whole alert, so it isn't repeated in the app.
    private func expire(_ timer: CookTimer) {
        guard let current = timers.first(where: { $0.id == timer.id && $0.deadline == timer.end }) else { return }
        timers.removeAll { $0.id == timer.id }; changed()
        guard current.usesAlarm != true else { return }
        finished.append(current)
        if TimerAlert.current != .silent { alerts.playFinishedSound() }
    }
}
