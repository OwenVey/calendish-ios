import SwiftUI

/// The hint revealed above the first week while pulling the meal plan down.
struct PullForEarlierWeek: View {
    let isArmed: Bool

    var body: some View {
        Label(isArmed ? "Release to load previous week" : "Pull to load previous week", systemImage: "arrow.down")
            .labelStyle(PullHintLabelStyle(isArmed: isArmed))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
            .animation(.snappy, value: isArmed)
            .accessibilityHidden(true)
    }
}
