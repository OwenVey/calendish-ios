import SwiftUI

/// Voice commands' progress, listening state, and recovery actions, shown above cook mode's step controls.
struct HandsFreeStatusBar: View {
    let handsFree: HandsFreeCooking
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            switch handsFree.status {
            case .off: EmptyView()
            case .starting:
                ProgressView()
                HandsFreeStatusText(text: "Starting voice commands…")
            case .preparing(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    HandsFreeStatusText(text: "Preparing voice commands")
                    ProgressView(value: progress).tint(CalendishStyle.accent)
                }
                Button("Cancel", action: handsFree.stop).modifier(GlassActionStyle())
            case .listening:
                Image(systemName: "waveform")
                    .foregroundStyle(CalendishStyle.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listening").font(.subheadline.weight(.semibold))
                    Text(handsFree.outcome ?? "Say “next”, “back”, or “start timer”")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Turn off", action: handsFree.stop).modifier(GlassActionStyle())
            case .paused:
                HandsFreeStatusText(text: "Voice commands paused")
                Button("Resume", action: handsFree.enable).modifier(GlassActionStyle())
                HandsFreeCloseButton(handsFree: handsFree)
            case .failed:
                HandsFreeStatusText(text: "Voice commands stopped unexpectedly")
                Button("Retry", action: handsFree.enable).modifier(GlassActionStyle())
                HandsFreeCloseButton(handsFree: handsFree)
            case .preparationFailed:
                HandsFreeStatusText(text: "Couldn’t prepare voice commands")
                Button("Retry", action: handsFree.enable).modifier(GlassActionStyle())
                HandsFreeCloseButton(handsFree: handsFree)
            case .microphoneDenied:
                HandsFreeStatusText(text: "Voice commands need microphone access. You can allow it in Settings.")
                Button("Open Settings", action: openSettings).modifier(GlassActionStyle())
                HandsFreeCloseButton(handsFree: handsFree)
            case .unavailable(let reason):
                HandsFreeStatusText(text: reason)
                HandsFreeCloseButton(handsFree: handsFree)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 56)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
