import SwiftUI

/// Turns off voice commands from the status bar.
struct HandsFreeCloseButton: View {
    let handsFree: HandsFreeCooking

    var body: some View {
        Button("Turn off voice commands", systemImage: "xmark", action: handsFree.stop)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .tint(Color.primary)
    }
}
