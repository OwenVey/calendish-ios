import SwiftUI

struct NotificationSettingsView: View {
    @State private var notifications = HouseholdNotifications.shared
    @State private var enabled = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle("Household recipes", isOn: $enabled)
                    .disabled(notifications.isUpdating)
                    .onChange(of: enabled) { _, value in
                        guard value != notifications.isEnabled else { return }
                        Task {
                            await notifications.setEnabled(value)
                            enabled = notifications.isEnabled
                        }
                    }
            } footer: {
                Text("Get notified when someone else adds a shared recipe to your household. This setting applies to this iPhone.")
            }
            if notifications.authorization == .denied {
                Section {
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Notifications are turned off for Calendish. Allow them in Settings to receive household alerts.")
                }
            }
            if notifications.isEnabled, notifications.canReceiveAlerts, !notifications.isRegistered {
                Section {
                    Button("Retry notification setup") { Task { await notifications.refresh() } }
                } footer: {
                    Text("Household notifications haven’t connected yet. Check your connection and try again.")
                }
            }
            if let error = notifications.errorMessage {
                Section { Text(error).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Notifications")
        .task {
            await notifications.refresh()
            enabled = notifications.isEnabled
        }
        .onChange(of: notifications.isEnabled) { _, value in enabled = value }
    }
}
