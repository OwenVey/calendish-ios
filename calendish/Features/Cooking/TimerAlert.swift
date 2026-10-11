import Foundation

/// How a finished cooking timer gets your attention.
nonisolated enum TimerAlert: String, CaseIterable, Identifiable {
    /// Rings through AlarmKit, like a Clock app timer, even in silent mode or a Focus.
    case alarm
    case notification
    case silent
    var id: Self { self }
    var title: String {
        switch self {
        case .alarm: "Alarm"
        case .notification: "Notification"
        case .silent: "Silent"
        }
    }
    static var current: TimerAlert {
        UserDefaults.standard.string(forKey: PreferenceKey.timerAlert).flatMap(TimerAlert.init) ?? .alarm
    }
}
