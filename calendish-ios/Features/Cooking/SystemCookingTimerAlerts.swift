import AlarmKit
import AudioToolbox
import SwiftUI
import UserNotifications

/// Cooking timer alerts through AlarmKit, user notifications, and system sounds.
struct SystemCookingTimerAlerts: CookingTimerAlerts {
    func authorizeAlarms() async -> Bool {
        let manager = AlarmManager.shared
        let state = manager.authorizationState == .notDetermined ? try? await manager.requestAuthorization() : manager.authorizationState
        return state == .authorized
    }

    func scheduleAlarm(for timer: CookTimer) async throws {
        let title: LocalizedStringResource = "\(timer.recipeTitle) · Step \(timer.stepIndex + 1)"
        let alert: AlarmPresentation.Alert = if #available(iOS 26.1, *) {
            AlarmPresentation.Alert(title: title)
        } else {
            AlarmPresentation.Alert(title: title, stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark"))
        }
        let attributes = AlarmAttributes<CookTimerAlarm>(presentation: AlarmPresentation(alert: alert), tintColor: CalendishStyle.accent)
        _ = try await AlarmManager.shared.schedule(id: timer.id, configuration: .alarm(schedule: .fixed(timer.end), attributes: attributes))
    }

    func authorizeNotifications() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func scheduleNotification(for timer: CookTimer, withSound: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = "\(timer.recipeTitle), step \(timer.stepIndex + 1): \(timer.durationText) timer finished."
        if withSound { content.sound = .default }
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: timer.id.uuidString, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.end.timeIntervalSinceNow), repeats: false)))
    }

    func withdraw(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        try? AlarmManager.shared.cancel(id: id)
    }

    func playFinishedSound() { AudioServicesPlayAlertSound(SystemSoundID(1005)) }
}
