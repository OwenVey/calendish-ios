import SwiftUI

/// Matches the launch screen (LaunchLogo centered on LaunchBackground) throughout loading.
struct LoadingView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            // The launch screen centers the logo in the full screen at its natural size, ignoring safe areas.
            Image("LaunchLogo")
                .accessibilityLabel("Loading Calendish")
        }
        .ignoresSafeArea()
    }
}
