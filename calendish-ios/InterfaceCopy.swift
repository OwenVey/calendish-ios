import Foundation

/// Shared display wording; persisted values and recipe text keep their original spelling.
nonisolated enum InterfaceCopy {
    static func servings(_ count: Int) -> String { count == 1 ? "1 serving" : "\(count) servings" }
    static func minutes(_ count: Int) -> String { count == 1 ? "1 minute" : "\(count) minutes" }
    static func rating(_ value: String) -> String { value == "1" ? "Rated 1 star" : "Rated \(value) stars" }

    /// Network failures have a useful remedy. Other failures retain the operation's recovery,
    /// without leaking service diagnostics or claiming an unconfirmed write was rolled back.
    static func failure(_ error: Error, action: String, recovery: String) -> String {
        "Couldn’t \(action). " + recoveryMessage(error, fallback: recovery)
    }

    static func recoveryMessage(_ error: Error, fallback: String) -> String {
        let network = error as NSError
        if network.domain == NSURLErrorDomain {
            return "Check your connection. \(fallback)"
        }
        return fallback
    }
}
