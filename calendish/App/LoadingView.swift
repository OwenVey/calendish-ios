import SwiftUI

/// Matches the launch screen (LaunchLogo centered on LaunchBackground) so there's no flash,
/// only showing a spinner below the logo if loading runs long.
struct LoadingView: View {
    @State private var showSpinner = false
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            // The launch screen centers the logo in the full screen at its natural size, ignoring safe areas.
            Image("LaunchLogo")
                .accessibilityLabel("Loading Calendish")
                .overlay(alignment: .bottom) {
                    if showSpinner {
                        ProgressView()
                            .controlSize(.large)
                            .alignmentGuide(.bottom) { $0[.top] - 48 }
                            .transition(.opacity)
                    }
                }
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation { showSpinner = true }
        }
    }
}
