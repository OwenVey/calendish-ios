import SwiftUI

/// A recipe tag on a tinted capsule. Muted pills are for tags that haven't been added yet.
struct TagPill: View {
    let tag: String
    var systemImage: String?
    var muted = false
    var body: some View {
        HStack(spacing: 4) {
            Text(tag).fixedSize(horizontal: false, vertical: true)
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)).imageScale(.small) }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }
}
