import SwiftUI

/// Matches the launch screen (a plain LaunchBackground) so there's no flash, only showing a spinner if loading runs long.
struct LoadingView: View {
    @State private var showSpinner = false
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            if showSpinner { ProgressView("Loading Calendish") }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            showSpinner = true
        }
    }
}
