import Foundation
import OSLog

/// A bounded local history for intermittent sync failures. No account IDs,
/// request URLs, credentials, response bodies, or user content are recorded.
@MainActor
enum HouseholdSyncDiagnostics {
    private static let logger = Logger(subsystem: "owenvey.calendish-ios", category: "HouseholdSync")
    static let fileURL = URL.cachesDirectory.appending(path: "household-sync-diagnostics.json")

    static func record(_ error: Error, source: String, action: String, phase: String) {
        let nsError = error as NSError
        let errorType = String(reflecting: type(of: error))
        let failureReason = reason(error)
        let entry: [String: String] = [
            "timestamp": Date.now.ISO8601Format(),
            "source": source, "action": action, "phase": phase,
            "errorType": errorType,
            "domain": nsError.domain, "code": String(nsError.code),
            "reason": failureReason,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        ]
        // All fields are metadata or fixed labels; raw error descriptions can
        // contain server payloads and must never be saved or logged here.
        logger.error("Sync failure: source=\(source, privacy: .public) type=\(errorType, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) reason=\(failureReason, privacy: .public)")
        do {
            let previous = (try? Data(contentsOf: fileURL)).flatMap {
                try? JSONDecoder().decode([[String: String]].self, from: $0)
            } ?? []
            let entries = Array((previous + [entry]).suffix(100))
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not persist sync diagnostics")
        }
    }

    private static func reason(_ error: Error) -> String {
        if error is DecodingError { return "response-decoding" }
        // SDK Realtime failures are package-private types. Recognize only
        // known fixed messages, without retaining any arbitrary description.
        switch error.localizedDescription {
        case "Maximum retry attempts reached.": return "realtime-retries-exhausted"
        case "Channel was closed by the server while subscribing.": return "realtime-channel-closed"
        default: return "unclassified"
        }
    }
}
