import Intents
import UIKit

/// Receives SiriKit requests in the app process. iOS launches the app in the background, without a scene, to handle them.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INAddTasksIntent ? GroceryTasksHandler() : nil
    }
}
