import Foundation

/// The system side of cooking timers: alarms, notifications, and the in-app finished sound.
/// Cooking timers decide when and whether an alert is still wanted; this only carries it out.
protocol CookingTimerAlerts {
    /// Whether AlarmKit may ring, asking the first time.
    func authorizeAlarms() async -> Bool
    func scheduleAlarm(for timer: CookTimer) async throws
    /// Whether notifications may alert, asking the first time.
    func authorizeNotifications() async throws -> Bool
    func scheduleNotification(for timer: CookTimer, withSound: Bool) async throws
    /// Withdraws any pending alarm or notification for a timer.
    func withdraw(_ id: UUID)
    /// Sounds a timer finishing while Calendish is open.
    func playFinishedSound()
}
