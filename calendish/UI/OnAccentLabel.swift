import SwiftUI

/// Bar buttons pick their own label color from the fill's brightness, which comes out black on basil,
/// so prominent toolbar actions set the on-accent color on the label itself, dimmed while disabled.
struct OnAccentLabel: View {
    var title: String
    var systemImage: String?
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Group {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .foregroundStyle(isEnabled ? AnyShapeStyle(CalendishStyle.onAccent) : AnyShapeStyle(.tertiary))
    }
}
