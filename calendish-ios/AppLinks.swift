import Foundation

/// Pages outside the app. Rows for links that aren't set yet stay hidden.
enum AppLinks {
    static let feedback = URL(string: "https://github.com/OwenVey/calendish-ios/issues/new")!
    /// The numeric ID from the app's App Store URL.
    static let appStoreID: String? = nil
    static let privacyPolicy: URL? = nil
    static let terms: URL? = nil
    static var writeReview: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }
}
