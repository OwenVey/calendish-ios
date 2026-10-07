import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CalendishStyle {
    static let accent = Color("AccentColor")
    /// Text and icons drawn on top of a solid accent fill.
    static let onAccent = Color("OnAccentColor")
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
}

struct RecipeArtwork: View {
    let recipe: Recipe
    var compact = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 14 : 24).fill(CalendishStyle.accent.opacity(0.09))
            Image(systemName: recipe.symbol)
                .font(.system(size: compact ? 25 : 64, weight: .light))
                .foregroundStyle(CalendishStyle.accent)
        }.accessibilityHidden(true)
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    var body: some View {
        HStack(spacing: 14) {
            RecipeArtwork(recipe: recipe, compact: true).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title).font(.headline).foregroundStyle(.primary)
                Text("\(recipe.minutes) min · \(recipe.servings) servings").font(.subheadline).foregroundStyle(.secondary)
                Text(recipe.tag).font(.caption).foregroundStyle(CalendishStyle.accent)
            }.padding(.vertical, 4)
        }
    }
}

/// A member's Google photo, or their initial when there's no photo.
struct MemberAvatar: View {
    let member: HouseholdMember?
    var size: CGFloat
    /// Google photo URLs end in a size like `=s96-c`; ask for one sharp enough for this screen.
    private var url: URL? {
        guard let url = member?.avatarURL else { return nil }
        let pixels = Int(size * 3)
        return URL(string: url.absoluteString.replacingOccurrences(of: #"=s\d+-c$"#, with: "=s\(pixels)-c", options: .regularExpression)) ?? url
    }
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    CalendishStyle.accent.opacity(0.18)
                    if let initial = member?.displayName.first {
                        Text(String(initial).uppercased())
                            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                            .foregroundStyle(CalendishStyle.accent)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(CalendishStyle.accent)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

struct GlassActionStyle: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent { content.buttonStyle(.glassProminent).foregroundStyle(CalendishStyle.onAccent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent).foregroundStyle(CalendishStyle.onAccent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}
