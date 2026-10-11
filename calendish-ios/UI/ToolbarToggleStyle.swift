import SwiftUI

/// A toolbar button that stays switched on, like voice commands: a solid neutral fill while on,
/// the plain toolbar glyph while off. Neutral rather than basil, so it reads as state, not as the screen's action.
struct ToolbarToggleStyle: ViewModifier {
    let isOn: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if isOn {
            content.buttonStyle(.glassProminent).tint(Color.primary).foregroundStyle(Color(.systemBackground))
        } else {
            content.toolbarGlyph()
        }
    }
}
