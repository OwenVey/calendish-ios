import Foundation

/// A page as it arrived, after following any redirects.
nonisolated struct LoadedPage: Sendable {
    var url: URL
    var status: Int
    var data: Data

    var isSuccess: Bool { (200..<300).contains(status) }
    var text: String? { String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) }
}
