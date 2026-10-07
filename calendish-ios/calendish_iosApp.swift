//
//  calendish_iosApp.swift
//  calendish-ios
//
//  Created by Owen Vey on 10/4/26.
//

import SwiftUI

@main
struct calendish_iosApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// Lets a screen (like cook mode) pin the interface to specific orientations.
@MainActor
enum OrientationLock {
    static private(set) var mask: UIInterfaceOrientationMask = .allButUpsideDown

    static func lock(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }

    static func unlock() {
        lock(.portrait)
        mask = .allButUpsideDown
    }
}
