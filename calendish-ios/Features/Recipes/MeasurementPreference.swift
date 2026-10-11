import Foundation

/// How recipe quantities and temperatures are shown. Saved recipes always keep the text as written.
nonisolated enum MeasurementPreference: String, CaseIterable, Identifiable, Sendable {
    case original, us, metric
    static let storageKey = "measurementUnits"
    var id: Self { self }
    var title: String {
        switch self {
        case .original: "As written"
        case .us: "US"
        case .metric: "Metric"
        }
    }
    var explanation: String {
        switch self {
        case .original: "Ingredient quantities appear exactly as each recipe lists them."
        case .us: "Converts ingredient quantities to US units, like cups and ounces, where possible. Saved recipes don’t change."
        case .metric: "Converts ingredient quantities to metric units, like grams and milliliters, where possible. Saved recipes don’t change."
        }
    }
    static var current: MeasurementPreference {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MeasurementPreference.init) ?? .original
    }
}
