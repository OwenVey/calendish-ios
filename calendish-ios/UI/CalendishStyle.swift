import SwiftUI

enum CalendishStyle {
    /// Basil green, the same in light and dark mode, for tints, icons, and solid fills alike.
    static let accent = Color("AccentColor")
    /// Text and icons drawn on top of a solid accent fill.
    static let onAccent = Color("OnAccentColor")
    /// Cook times and timers, matching the system Clock app and the cooking Live Activity.
    static let timer = Color.orange
    /// Oven and food temperatures in recipe steps, apart from the accent ingredients and orange times.
    static let temperature = Color.red
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
}
