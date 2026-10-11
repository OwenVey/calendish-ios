import ActivityKit
import AlarmKit
import SwiftUI
import UserNotifications

struct CookingSettingsView: View {
    @AppStorage(PreferenceKey.keepScreenAwake) private var keepScreenAwake = true
    @AppStorage(PreferenceKey.showCookIngredients) private var showIngredients = true
    @AppStorage(PreferenceKey.liveActivity) private var liveActivity = true
    @AppStorage(PreferenceKey.timerAlert) private var timerAlert = TimerAlert.alarm
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var notifications: UNAuthorizationStatus?
    @State private var activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var alarms = AlarmManager.shared.authorizationState
    private var notificationsAllowed: Bool { [.authorized, .provisional, .ephemeral].contains(notifications) }
    /// False until the status loads, so the footer doesn't flash a permission prompt.
    private var notificationsOff: Bool { notifications != nil && !notificationsAllowed }
    var body: some View {
        Form {
            Section {
                Toggle("Keep screen awake", isOn: $keepScreenAwake)
            } footer: {
                Text("Your screen stays on while cook mode is open.")
            }
            Section {
                Toggle("Start with ingredients open", isOn: $showIngredients)
            } footer: {
                Text("Cook mode opens with the ingredients sheet showing. You can collapse it anytime.")
            }
            Section {
                Toggle("Live Activity", isOn: $liveActivity)
                if liveActivity && !activitiesAllowed {
                    Button("Open Calendish settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } footer: {
                Text(liveActivity && !activitiesAllowed
                    ? "Live Activities are turned off for Calendish in the Settings app."
                    : "Follow the current step and start timers from the Lock Screen and Dynamic Island.")
            }
            Section {
                Picker("Alert", selection: $timerAlert) {
                    ForEach(TimerAlert.allCases) { Text($0.title).tag($0) }
                }
                .tint(.secondary)
                if timerAlert == .alarm {
                    if alarms == .notDetermined {
                        Button("Allow alarms") {
                            Task { alarms = (try? await AlarmManager.shared.requestAuthorization()) ?? AlarmManager.shared.authorizationState }
                        }
                    } else if alarms == .denied {
                        Button("Open Calendish settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } else if let notifications {
                    LabeledContent("Notifications", value: notificationsAllowed ? "On" : "Off")
                    if notifications == .notDetermined {
                        Button("Allow notifications") {
                            Task {
                                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                await loadNotificationStatus()
                            }
                        }
                    } else {
                        Button("Open notification settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                }
            } header: {
                Text("Timers")
            } footer: {
                Text(timerFooter)
            }
        }
        .navigationTitle("Cooking")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
            alarms = AlarmManager.shared.authorizationState
            Task { await loadNotificationStatus() }
        }
    }
    private var timerFooter: String {
        switch timerAlert {
        case .alarm where alarms == .notDetermined:
            "Allow alarms so timers can ring even when your iPhone is on silent or in a Focus."
        case .alarm where alarms == .denied:
            "Alarms are off. Timers use notifications when allowed."
        case .alarm: "Timers ring like the Clock app, even when your iPhone is on silent or in a Focus."
        case .notification where notificationsOff: "Timers play a sound in Calendish. Turn on notifications to hear them when you’re in another app."
        case .notification: "Timers play a sound and show a notification."
        case .silent where notificationsOff: "Timers finish without sound. Turn on notifications to see them when you’re in another app."
        case .silent: "Timers show a notification without sound."
        }
    }
    private func loadNotificationStatus() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
