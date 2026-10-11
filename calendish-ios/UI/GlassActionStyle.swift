import SwiftUI

/// The app's only button chrome. Prominent buttons are the screen's primary action, drawn in the accent
/// with the on-accent label color.
struct GlassActionStyle: ViewModifier {
    var prominent = false
    func body(content: Content) -> some View {
        if prominent { content.buttonStyle(.glassProminent).foregroundStyle(CalendishStyle.onAccent) }
        else { content.buttonStyle(.glass) }
    }
}
