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
    static var current: MeasurementPreference {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MeasurementPreference.init) ?? .original
    }
}
