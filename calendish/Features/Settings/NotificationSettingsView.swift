import SwiftUI

struct NotificationSettingsView: View {
    @State private var notifications = HouseholdNotifications.shared
    /// Follows each tap right away while permission and registration catch up.
    @State private var selected: Set<NotificationTopic> = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                ForEach(NotificationTopic.allCases) { topic in
                    Toggle(isOn: binding(topic)) {
                        Text(topic.title)
                        Text(topic.detail)
                    }
                }
                .disabled(notifications.isUpdating)
            } header: {
                Text("Household")
            } footer: {
                Text("You won’t be notified about your own changes. These settings apply to this iPhone.")
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
            selected = notifications.topics
        }
        .onChange(of: notifications.topics) { _, value in selected = value }
    }

    private func binding(_ topic: NotificationTopic) -> Binding<Bool> {
        Binding {
            selected.contains(topic)
        } set: { value in
            guard value != notifications.isEnabled(topic) else { return }
            if value { selected.insert(topic) } else { selected.remove(topic) }
            Task {
                await notifications.setEnabled(topic, value)
                selected = notifications.topics
            }
        }
    }
}
