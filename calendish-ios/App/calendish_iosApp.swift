//
//  calendish_iosApp.swift
//  calendish-ios
//
//  Created by Owen Vey on 10/4/26.
//

import SwiftUI

@main
struct calendish_iosApp: App {
    init() { PreferenceKey.registerDefaults() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
