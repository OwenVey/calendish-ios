import UIKit
import UserNotifications

/// Bridges the system's APNs callbacks into the app's notification coordinator.
final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        HouseholdNotifications.shared.receivedDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        HouseholdNotifications.shared.registrationFailed()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let recipe = RecipeNotification(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { HouseholdNotifications.shared.pendingRecipe = recipe }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let recipe = RecipeNotification(userInfo: notification.request.content.userInfo) else {
            // Cooking timers already present their own in-app alert and sound.
            return []
        }
        return await MainActor.run { HouseholdNotifications.shared.shouldPresent(recipe) ? [.banner, .list, .sound] : [] }
    }
}
