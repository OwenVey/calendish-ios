//
//  CalendishApp.swift
//  calendish
//
//  Created by Owen Vey on 10/4/26.
//

import SwiftUI

@main
struct CalendishApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    init() { PreferenceKey.registerDefaults() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
