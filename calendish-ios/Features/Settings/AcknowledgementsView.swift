import SwiftUI

/// Open-source packages Calendish ships with, from Package.resolved. Update this list when dependencies change.
struct AcknowledgementsView: View {
    private struct Package: Identifiable {
        let name: String
        let license: String
        let url: URL
        var id: String { name }
        init(_ name: String, _ license: String, _ url: String) {
            self.name = name
            self.license = license
            self.url = URL(string: url)!
        }
    }
    private let packages = [
        Package("AppAuth", "Apache 2.0", "https://github.com/openid/AppAuth-iOS"),
        Package("AppCheck", "Apache 2.0", "https://github.com/google/app-check"),
        Package("Google Sign-In", "Apache 2.0", "https://github.com/google/GoogleSignIn-iOS"),
        Package("GoogleUtilities", "Apache 2.0", "https://github.com/google/GoogleUtilities"),
        Package("GTMAppAuth", "Apache 2.0", "https://github.com/google/GTMAppAuth"),
        Package("GTM Session Fetcher", "Apache 2.0", "https://github.com/google/gtm-session-fetcher"),
        Package("Interop for Google SDKs", "Apache 2.0", "https://github.com/google/interop-ios-for-google-sdks"),
        Package("Promises", "Apache 2.0", "https://github.com/google/promises"),
        Package("Supabase", "MIT", "https://github.com/supabase/supabase-swift"),
        Package("Swift ASN.1", "Apache 2.0", "https://github.com/apple/swift-asn1"),
        Package("Swift Clocks", "MIT", "https://github.com/pointfreeco/swift-clocks"),
        Package("Swift Concurrency Extras", "MIT", "https://github.com/pointfreeco/swift-concurrency-extras"),
        Package("Swift Crypto", "Apache 2.0", "https://github.com/apple/swift-crypto"),
        Package("Swift HTTP Types", "Apache 2.0", "https://github.com/apple/swift-http-types"),
        Package("Swift Issue Reporting", "MIT", "https://github.com/pointfreeco/swift-issue-reporting"),
        Package("XCTest Dynamic Overlay", "MIT", "https://github.com/pointfreeco/xctest-dynamic-overlay")
    ]
    var body: some View {
        Form {
            Section {
                ForEach(packages) { package in
                    Link(destination: package.url) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(package.name).foregroundStyle(.primary)
                                Text(package.license).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityHint("Opens the project and its license on GitHub.")
                }
            } footer: {
                Text("Calendish is built with these open-source projects. Tap one to read its license.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AcknowledgementsView() }
}
