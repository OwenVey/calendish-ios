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
    @State private var store: HouseholdStore
    init() {
        PreferenceKey.registerDefaults()
        _store = State(initialValue: HouseholdStore(beforeSignOut: { await HouseholdNotifications.shared.unregisterBeforeSignOut() }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
