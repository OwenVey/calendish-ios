import Observation
import Supabase
import UIKit
import UserNotifications

/// Owns this installation's opt-in, APNs registration, and account-safe notification routing.
@MainActor
@Observable
final class HouseholdNotifications {
    static let shared = HouseholdNotifications()
    /// The household alerts this account turned on for this installation.
    private(set) var topics: Set<NotificationTopic> = []
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var isUpdating = false
    private(set) var isRegistered = false
    var errorMessage: String?
    var pendingAlert: HouseholdAlert?
    var isOfferingSetup = false

    private var accountID: UUID?
    private var deviceToken: String?
    private var registrationTask: Task<Void, Error>?
    private let installation: UUID
    private let defaults: UserDefaults
    private let transport: HouseholdPushTransport

    init(client: SupabaseClient? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transport = HouseholdPushTransport(client: client ?? supabase)
        let key = "pushInstallationID"
        if let value = defaults.string(forKey: key), let id = UUID(uuidString: value) { installation = id }
        else {
            installation = UUID()
            defaults.set(installation.uuidString, forKey: key)
        }
    }

    func setAccount(_ id: UUID?) async {
        // Preview and workflow stores never register devices for their fixture accounts.
        guard id == transport.client.auth.currentUser?.id else { return }
        if accountID != id {
            accountID = id
            pendingAlert = pendingAlert?.recipientID == id ? pendingAlert : nil
            isRegistered = false
            topics = id.map(storedTopics) ?? []
        }
        await refresh()
    }

    /// Rechecks system permission on return from Settings, and retries an interrupted registration.
    /// Installations that never opted in stay off the server; turning alerts off syncs through `setEnabled`.
    func refresh() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard accountID != nil, isEnabled else { return }
        if canReceiveAlerts { UIApplication.shared.registerForRemoteNotifications() }
        do { try await synchronize(); errorMessage = nil }
        catch { errorMessage = "Couldn’t update notifications. Check your connection and try again." }
    }

    var canReceiveAlerts: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    var isEnabled: Bool { !topics.isEmpty }

    func isEnabled(_ topic: NotificationTopic) -> Bool { topics.contains(topic) }

    /// Membership changes are rare and important, so they turn on with the first other topic until someone turns them off.
    func setEnabled(_ topic: NotificationTopic, _ enabled: Bool) async {
        guard let accountID else { return }
        var updated = topics
        if enabled {
            updated.insert(topic)
            if defaults.object(forKey: NotificationTopic.membership.preferenceKey(accountID)) == nil { updated.insert(.membership) }
        } else {
            updated.remove(topic)
        }
        await setTopics(updated)
    }

    func setTopics(_ updated: Set<NotificationTopic>) async {
        guard let accountID, !isUpdating, updated != topics else { return }
        isUpdating = true
        defer { isUpdating = false }
        errorMessage = nil
        do {
            let added = !updated.isSubset(of: topics)
            if added {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                guard canReceiveAlerts else { return }
            }
            guard self.accountID == accountID else { return }
            let previous = topics
            topics = updated
            do { try await synchronize() }
            catch {
                if self.accountID == accountID { topics = previous }
                throw error
            }
            // A suspended request must not save a preference into a different account.
            guard self.accountID == accountID else { return }
            for topic in NotificationTopic.allCases { defaults.set(updated.contains(topic), forKey: topic.preferenceKey(accountID)) }
            if added { UIApplication.shared.registerForRemoteNotifications() }
            await removeAlerts(previous.subtracting(updated))
        } catch {
            errorMessage = "Couldn’t update notifications. Check your connection and try again."
        }
    }

    /// Offered once after household setup. iOS asks only once, so people who already chose aren't asked again.
    func offerAfterSetup() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard accountID != nil, !isEnabled else { return }
        switch authorization {
        case .notDetermined:
            errorMessage = nil
            isOfferingSetup = true
        case .denied: break
        default: await setTopics(Set(NotificationTopic.allCases))
        }
    }

    func receivedDeviceToken(_ token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        Task {
            do { try await synchronize(); errorMessage = nil }
            catch {
                if isEnabled { errorMessage = "Couldn’t turn on household notifications. Check your connection and try again." }
            }
        }
    }

    func registrationFailed() {
        isRegistered = false
        if isEnabled { errorMessage = "Couldn’t turn on household notifications. Check your connection and try again." }
    }

    /// Revoke before signing out, while the session can still authenticate the request.
    /// Waiting for earlier writes prevents a delayed registration from restoring the association.
    /// Best effort: signing out must work offline, and ending the session removes the device server-side.
    func unregisterBeforeSignOut() async {
        accountID = nil
        pendingAlert = nil
        _ = try? await registrationTask?.value
        try? await transport.unregister(installation: installation)
        isRegistered = false
        topics = []
        await removeAlerts(Set(NotificationTopic.allCases))
    }

    func shouldPresent(_ alert: HouseholdAlert) -> Bool {
        topics.contains(alert.topic) && alert.recipientID == transport.client.auth.currentUser?.id
    }

    private func storedTopics(_ account: UUID) -> Set<NotificationTopic> {
        var stored = Set(NotificationTopic.allCases.filter { defaults.bool(forKey: $0.preferenceKey(account)) })
        // Before membership alerts existed, turning on recipes was the only household opt-in.
        if defaults.object(forKey: NotificationTopic.membership.preferenceKey(account)) == nil, stored.contains(.recipes) {
            stored.insert(.membership)
        }
        return stored
    }

    private func synchronize() async throws {
        guard let accountID else { return }
        let token = deviceToken
        let enabled = canReceiveAlerts ? topics : []
        if !enabled.isEmpty, token == nil { return }
        let previous = registrationTask
        let task = Task {
            _ = try? await previous?.value
            guard self.accountID == accountID, self.transport.client.auth.currentUser?.id == accountID else { return }
            if let token { try await self.transport.register(installation: self.installation, token: token, topics: enabled) }
            else { try await self.transport.unregister(installation: self.installation) }
            if self.accountID == accountID { self.isRegistered = !enabled.isEmpty }
        }
        registrationTask = task
        try await task.value
    }

    private func removeAlerts(_ removed: Set<NotificationTopic>) async {
        guard !removed.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let alerts = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: alerts.filter {
            HouseholdAlert(userInfo: $0.request.content.userInfo).map { removed.contains($0.topic) } ?? false
        }.map(\.request.identifier))
    }
}
