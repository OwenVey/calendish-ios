import Foundation

/// Household invitations travel as `calendish://join/<code>` links or as the bare code.
nonisolated enum HouseholdInvite {
    static func link(for code: String) -> URL { URL(string: "calendish://join/\(code)")! }

    /// The invite code in a join link, or nil for any other URL.
    static func code(from url: URL) -> String? {
        guard url.scheme == "calendish", url.host == "join" else { return nil }
        let code = url.pathComponents.dropFirst().first
            ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
        return code.map(normalized).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
