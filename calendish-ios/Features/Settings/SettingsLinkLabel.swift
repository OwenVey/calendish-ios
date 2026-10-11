import SwiftUI

/// A settings row that leaves the app, marked with the outward arrow Settings uses for links.
struct SettingsLinkLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }
    var body: some View {
        HStack {
            SettingsLabel(title, systemImage: systemImage, color: color).foregroundStyle(Color.primary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }
}
