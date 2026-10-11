import SwiftUI

/// A settings row title with the Settings app's white glyph on a colored rounded square.
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }
    var body: some View {
        Label {
            Text(title)
        } icon: {
            // Wide symbols scale down to fit the square's inset instead of spilling past its edges.
            ViewThatFits(in: .horizontal) {
                Image(systemName: systemImage)
                Image(systemName: systemImage).resizable().scaledToFit()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 21, height: 21)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: .rect(cornerRadius: 7))
        }
    }
}
