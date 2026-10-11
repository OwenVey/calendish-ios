import Foundation

/// The scale recipe temperatures are shown in, everywhere a step appears. Saved recipes always keep the text as written.
nonisolated enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case fahrenheit, celsius
    static let storageKey = "temperatureUnit"
    var id: Self { self }
    var title: String {
        switch self {
        case .fahrenheit: "Fahrenheit (°F)"
        case .celsius: "Celsius (°C)"
        }
    }
    /// Follows the region's measurement system until the cook picks one.
    static var system: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
    static var current: TemperatureUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(TemperatureUnit.init) ?? system
    }
}
