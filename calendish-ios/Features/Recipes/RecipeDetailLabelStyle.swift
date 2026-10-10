import SwiftUI

/// A recipe detail with a small icon tucked close to its text.
struct RecipeDetailLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption).accessibilityHidden(true)
            configuration.title
        }
    }
}
