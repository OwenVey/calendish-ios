import SwiftUI

/// Explains household alerts before iOS's one-time permission prompt, so declining here can be revisited in Settings.
struct NotificationOfferView: View {
    @State private var notifications = HouseholdNotifications.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CalendishStyle.accent)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Stay in step with your household").font(.title.bold()).fontDesign(.rounded)
                    Text("Get notified when someone adds a recipe or groceries, or joins your household. You can choose which alerts you get anytime in Settings.")
                        .font(.body).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                if let error = notifications.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                AuthButton(title: "Turn on notifications", working: notifications.isUpdating, workingTitle: "Turning on notifications") {
                    Task {
                        await notifications.setTopics(Set(NotificationTopic.allCases))
                        if notifications.errorMessage == nil { dismiss() }
                    }
                }
                Button { dismiss() } label: {
                    Text("Not now").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                }
                .modifier(GlassActionStyle())
                .controlSize(.large)
                .tint(.primary)
            }
            .disabled(notifications.isUpdating)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
            .frame(maxWidth: 500)
        }
        .interactiveDismissDisabled(notifications.isUpdating)
    }
}
