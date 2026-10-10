import SwiftUI

struct ShareView: View {
    var status: ShareStatus
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch status.state {
            case .saving:
                ProgressView("Sending to Calendish…").font(.headline)
            case .saved:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Ready to import").font(.headline)
                Text("Open Calendish to review and save the recipe.").font(.subheadline).foregroundStyle(.secondary)
            case .unsupported, .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Couldn’t send to Calendish").font(.headline)
                Text(status.state == .unsupported
                    ? "Share a recipe link, recipe text, photos, or a PDF."
                    : "Open Calendish and try importing the recipe there.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if status.state != .saving {
                Button("Done", action: onDone).buttonStyle(.glass).padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: 340)
        .glassEffect(in: .rect(cornerRadius: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Color(red: 0.055, green: 0.624, blue: 0.431))
    }
}
