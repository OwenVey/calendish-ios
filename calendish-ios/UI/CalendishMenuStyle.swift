import SwiftUI

/// Preserves native menu rendering and lets action roles choose colors instead of the app's forced tint.
struct CalendishMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .tint(nil)
    }
}
