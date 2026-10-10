import SwiftUI

/// The app icon drawn in SwiftUI, laid out on the same 1024-point grid as design/Calendish.icon.
struct BrandIcon: View {
    var size: CGFloat = 96
    private static let background = LinearGradient(
        colors: [Color(red: 0.224, green: 0.690, blue: 0.533), Color(red: 0.055, green: 0.624, blue: 0.431)],
        startPoint: .top, endPoint: .bottom)
    private static let paper = Color(red: 0.961, green: 0.957, blue: 0.910)
    private static let header = Color(red: 0.624, green: 0.851, blue: 0.773)
    private static let utensils = Color(red: 0.055, green: 0.624, blue: 0.431)

    var body: some View {
        let u = size / 1024
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Self.background)
            RoundedRectangle(cornerRadius: 114 * u, style: .continuous)
                .fill(Self.paper)
                .frame(width: 668 * u, height: 638 * u)
                .offset(x: 178 * u, y: 218 * u)
            UnevenRoundedRectangle(topLeadingRadius: 114 * u, topTrailingRadius: 114 * u, style: .continuous)
                .fill(Self.header)
                .frame(width: 668 * u, height: 128 * u)
                .offset(x: 178 * u, y: 218 * u)
            ForEach([332, 648], id: \.self) { x in
                Capsule()
                    .fill(Self.paper)
                    .frame(width: 44 * u, height: 99 * u)
                    .offset(x: CGFloat(x) * u, y: 171 * u)
            }
            Image(systemName: "fork.knife")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Self.utensils)
                .frame(width: 668 * u, height: 350 * u)
                .offset(x: 178 * u, y: 426 * u)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }
}
