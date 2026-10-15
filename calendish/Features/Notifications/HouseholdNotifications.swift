import Observation
import Supabase
import UIKit
import UserNotifications

/// Owns this installation's opt-in, APNs registration, and account-safe notification routing.
@MainActor
@Observable
final class HouseholdNotifications {
    static let shared = HouseholdNotifications()
    private(set) var isEnabled = false
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var isUpdating = false
    private(set) var isRegistered = false
    var errorMessage: String?
    var pendingRecipe: RecipeNotification?
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
            pendingRecipe = pendingRecipe?.recipientID == id ? pendingRecipe : nil
            isRegistered = false
            isEnabled = id.map { defaults.bool(forKey: preferenceKey($0)) } ?? false
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

    func setEnabled(_ enabled: Bool) async {
        guard let accountID, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        errorMessage = nil
        do {
            if enabled {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                guard canReceiveAlerts else { return }
            }
            guard self.accountID == accountID else { return }
            let previous = isEnabled
            isEnabled = enabled
            do { try await synchronize() }
            catch {
                if self.accountID == accountID { isEnabled = previous }
                throw error
            }
            // A suspended request must not save a preference into a different account.
            guard self.accountID == accountID else { return }
            defaults.set(enabled, forKey: preferenceKey(accountID))
            if enabled { UIApplication.shared.registerForRemoteNotifications() }
            else { await removeRecipeAlerts() }
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
        default: await setEnabled(true)
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
        pendingRecipe = nil
        _ = try? await registrationTask?.value
        try? await transport.unregister(installation: installation)
        isRegistered = false
        isEnabled = false
        await removeRecipeAlerts()
    }

    func shouldPresent(_ recipe: RecipeNotification) -> Bool {
        isEnabled && recipe.recipientID == transport.client.auth.currentUser?.id
    }

    private func preferenceKey(_ account: UUID) -> String { "householdRecipeNotifications.\(account.uuidString)" }

    private func synchronize() async throws {
        guard let accountID else { return }
        let token = deviceToken
        let enabled = isEnabled && canReceiveAlerts
        if enabled, token == nil { return }
        let previous = registrationTask
        let task = Task {
            _ = try? await previous?.value
            guard self.accountID == accountID, self.transport.client.auth.currentUser?.id == accountID else { return }
            if let token { try await self.transport.register(installation: self.installation, token: token, enabled: enabled) }
            else { try await self.transport.unregister(installation: self.installation) }
            if self.accountID == accountID { self.isRegistered = enabled }
        }
        registrationTask = task
        try await task.value
    }

    private func removeRecipeAlerts() async {
        let center = UNUserNotificationCenter.current()
        let alerts = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: alerts.filter {
            RecipeNotification(userInfo: $0.request.content.userInfo) != nil
        }.map(\.request.identifier))
    }
}
