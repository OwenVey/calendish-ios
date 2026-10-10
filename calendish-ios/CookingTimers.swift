import AlarmKit
import AudioToolbox
import SwiftUI
import UserNotifications
import Observation

/// End dates persist independently of cooking screens; system alarms or notifications cover background expiration.
@Observable
final class CookingTimers {
    static let shared = CookingTimers()
    private(set) var timers: [CookTimer] = []
    var finished: [CookTimer] = []
    var isCooking = false
    var notificationWarning: String?
    @ObservationIgnored private(set) var schedulingTask: Task<Void, Never>?
    private let storageKey = "activeCookingTimers"
    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey), let saved = try? JSONDecoder().decode([CookTimer].self, from: data) { timers = saved }
    }
    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(timers), forKey: storageKey)
        CookingSession.shared.refresh()
    }
    func start(recipe: Recipe, stepIndex: Int, duration: TimeInterval) {
        guard duration > 0 else { return }
        let timer = CookTimer(recipe: recipe, stepIndex: stepIndex, duration: duration)
        timers.append(timer); persist()
        schedulingTask = Task {
            let alert = TimerAlert.current
            if alert == .alarm, await scheduleAlarm(for: timer) { return }
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    notificationWarning = "Notifications are off. Keep Calendish open to see timer alerts, or allow notifications in Settings."
                    return
                }
                notificationWarning = nil
                guard timers.contains(where: { $0.id == timer.id }), timer.end > .now else { return }
                let content = UNMutableNotificationContent()
                content.title = "Timer finished"
                content.body = "\(timer.recipeTitle), step \(timer.stepIndex + 1): \(timer.durationText) timer finished."
                if alert != .silent { content.sound = .default }
                try await center.add(UNNotificationRequest(identifier: timer.id.uuidString, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.end.timeIntervalSinceNow), repeats: false)))
                if !timers.contains(where: { $0.id == timer.id }) { center.removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString]) }
            } catch { notificationWarning = "Couldn’t schedule a timer notification. Keep Calendish open for the alert." }
        }
    }
    /// Schedules a system alarm for the timer's end. Returns false, so a notification takes over,
    /// when alarms aren't allowed or scheduling fails.
    private func scheduleAlarm(for timer: CookTimer) async -> Bool {
        let manager = AlarmManager.shared
        do {
            let state = manager.authorizationState == .notDetermined ? try await manager.requestAuthorization() : manager.authorizationState
            guard state == .authorized, timers.contains(where: { $0.id == timer.id }), timer.end > .now else { return false }
            let title: LocalizedStringResource = "\(timer.recipeTitle) · Step \(timer.stepIndex + 1)"
            let alert: AlarmPresentation.Alert = if #available(iOS 26.1, *) {
                AlarmPresentation.Alert(title: title)
            } else {
                AlarmPresentation.Alert(title: title, stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark"))
            }
            let attributes = AlarmAttributes<CookTimerAlarm>(presentation: AlarmPresentation(alert: alert), tintColor: CalendishStyle.accent)
            _ = try await manager.schedule(id: timer.id, configuration: .alarm(schedule: .fixed(timer.end), attributes: attributes))
            guard let index = timers.firstIndex(where: { $0.id == timer.id }) else {
                try? manager.cancel(id: timer.id)
                return true
            }
            timers[index].usesAlarm = true; persist()
            notificationWarning = nil
            return true
        } catch { return false }
    }
    func acknowledge() { finished.removeAll() }
    func cancel(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }; persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
        try? AlarmManager.shared.cancel(id: timer.id)
    }
    func waitForNextTimer() async {
        guard let next = timers.min(by: { $0.end < $1.end }) else { return }
        do { try await Task.sleep(for: .seconds(max(0, next.end.timeIntervalSinceNow))) } catch { return }
        guard !Task.isCancelled else { return }
        timers.removeAll { $0.id == next.id }; persist()
        guard next.usesAlarm != true else { return }
        finished.append(next)
        if TimerAlert.current != .silent { AudioServicesPlayAlertSound(SystemSoundID(1005)) }
    }
}
