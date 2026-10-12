import SwiftUI

/// A recipe book row drawn as a card, which dims inside its rounded corners when pressed instead of the list's square highlight.
struct RecipeCardButtonStyle: ButtonStyle {
    static let cornerRadius: CGFloat = 20
    static let padding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        configuration.label
            .padding(.leading, Self.padding)
            .padding(.trailing, 14)
            .padding(.vertical, Self.padding - 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CalendishStyle.surface, in: shape)
            .overlay { shape.fill(Color(.systemFill)).opacity(configuration.isPressed ? 1 : 0) }
            .contentShape(.contextMenuPreview, shape)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
