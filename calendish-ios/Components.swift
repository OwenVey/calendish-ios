import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "Device setting"
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
    /// Basil green, the same in light and dark mode, for tints, icons, and solid fills alike.
    static let accent = Color("AccentColor")
    /// Text and icons drawn on top of a solid accent fill.
    static let onAccent = Color("OnAccentColor")
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
}

/// Preserves native menu rendering and lets action roles choose colors instead of the app's forced tint.
struct CalendishMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .tint(nil)
    }
}

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

/// A recipe's photo, or its symbol on a tinted tile when it has none.
struct RecipeArtwork: View {
    let recipe: Recipe
    var compact = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 14 : 24)
        ZStack {
            shape.fill(Color(.tertiarySystemFill))
            if let path = recipe.imagePath {
                RecipePhoto(path: path, thumbnail: compact)
            } else {
                Image(systemName: recipe.symbol)
                    .font(.system(size: compact ? 25 : 64, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

struct RecipeRow: View {
    @Environment(HouseholdStore.self) private var store
    let recipe: Recipe
    /// Servings to show instead of the recipe's own, such as a planned meal's.
    var servings: Int?
    /// Whether to name whose recipe it is.
    var showsOwner = true
    /// The household's rating and cooked history, shown when there is some.
    var stats: RecipeStats?
    var showsLastCooked = false
    /// A line under the details, such as why a recipe is suggested.
    var caption: String?
    /// Whose recipe it is. Your own recipes don't name an owner.
    private var owner: String? { !showsOwner || store.isMine(recipe) ? nil : store.ownerName(of: recipe) }
    var body: some View {
        HStack(spacing: 14) {
            RecipeArtwork(recipe: recipe, compact: true).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(recipe.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    if store.isMine(recipe) && recipe.owner?.isShared == false {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Only me")
                    }
                    if recipe.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).accessibilityLabel("Favorite")
                    }
                }
                if let owner {
                    Text(recipe.owner?.person == nil ? "Owned by the household" : "\(owner)’s recipe").font(.footnote).foregroundStyle(.secondary).lineLimit(1).padding(.top, -4)
                }
                HStack(spacing: 10) {
                    Label("\(recipe.minutes) min", systemImage: "clock")
                    Label(InterfaceCopy.servings(servings ?? recipe.servings), systemImage: "person.2")
                    if let rating = stats?.averageRating {
                        Label(Self.formatted(rating), systemImage: "star")
                            .accessibilityLabel(InterfaceCopy.rating(Self.formatted(rating)))
                    }
                }
                .labelStyle(RecipeDetailLabelStyle())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if let caption = caption ?? (showsLastCooked ? CookedHistory.lastCookedText(stats?.history) : nil) {
                    Text(caption).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                if !recipe.tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(recipe.tags.prefix(2), id: \.self) { TagPill(tag: $0, compact: true) }
                        if recipe.tags.count > 2 {
                            Text("+\(recipe.tags.count - 2)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.vertical, 4)
        }
    }
}

extension RecipeRow {
    /// An average rating like "4.5", or "4" when whole.
    static func formatted(_ rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// A recipe detail with a small icon tucked close to its text.
private struct RecipeDetailLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption).accessibilityHidden(true)
            configuration.title
        }
    }
}

/// A recipe tag on a tinted capsule. Muted pills are for tags that haven't been added yet.
struct TagPill: View {
    let tag: String
    var systemImage: String? = nil
    var compact = false
    var muted = false
    var body: some View {
        HStack(spacing: 4) {
            Text(tag).fixedSize(horizontal: false, vertical: true)
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)).imageScale(.small) }
        }
        .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 3 : 6)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }
}

/// Lays out views left to right, wrapping onto a new line when a row runs out of room.
/// Views in a row are centered vertically on each other.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: layout.width, height: layout.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, layout.origins) {
            let size = measuredSize(subview, width: bounds.width)
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(size))
        }
    }
    private func measuredSize(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        return ideal.width > width ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var row: [(index: Int, height: CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        func centerRow() {
            for item in row { origins[item.index].y += (rowHeight - item.height) / 2 }
            row = []
        }
        for subview in subviews {
            let size = measuredSize(subview, width: width)
            if x > 0 && x + size.width > width {
                centerRow()
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            row.append((origins.count, size.height))
            origins.append(CGPoint(x: x, y: y))
            maxX = max(maxX, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        centerRow()
        return (origins, maxX, y + rowHeight)
    }
}

/// A member's Google photo, or their initial when there's no photo.
struct MemberAvatar: View {
    let member: HouseholdMember?
    var size: CGFloat
    /// Google photo URLs end in a size like `=s96-c`; ask for one sharp enough for this screen.
    private var url: URL? {
        guard let url = member?.avatarURL, url != ProfilePhotos.removedReference else { return nil }
        let pixels = Int(size * 3)
        return URL(string: url.absoluteString.replacingOccurrences(of: #"=s\d+-c$"#, with: "=s\(pixels)-c", options: .regularExpression)) ?? url
    }
    @State private var loadedAvatar: (url: URL, image: UIImage)?
    var body: some View {
        AsyncImage(url: ProfilePhotos.path(for: url) == nil ? url : nil) { phase in
            if let loadedAvatar, loadedAvatar.url == url {
                Image(uiImage: loadedAvatar.image).resizable().scaledToFill()
            } else if let image = phase.image {
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
        .task(id: url) {
            guard let url, ProfilePhotos.path(for: url) != nil else { loadedAvatar = nil; return }
            if let image = await ProfilePhotos.shared.image(for: url) { loadedAvatar = (url, image) }
        }
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

extension View {
    /// Native alerts use a neutral tint for secondary actions, including Cancel. The system's
    /// default action retains the app's accent fill; destructive roles retain their red color.
    /// An independent presenter keeps this tint from affecting the screen's ordinary controls.
    func calendishAlert<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        background {
            Color.clear.frame(width: 0, height: 0)
                .alert(Text(title), isPresented: isPresented, actions: actions, message: message)
                .tint(Color.primary)
        }
    }

    func calendishAlert<Data, Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>, presenting data: Data?,
        @ViewBuilder actions: @escaping (Data) -> Actions,
        @ViewBuilder message: @escaping (Data) -> Message
    ) -> some View {
        background {
            Color.clear.frame(width: 0, height: 0)
                .alert(Text(title), isPresented: isPresented, presenting: data, actions: actions, message: message)
                .tint(Color.primary)
        }
    }

    /// Shared title and list spacing for top-level tab screens, so switching tabs never shifts the header or first section.
    /// The zero top margin drops the grouped list's default gap, so content starts where a search field would.
    func tabRootStyle() -> some View {
        toolbarTitleDisplayMode(.inlineLarge).listSectionSpacing(.compact).contentMargins(.top, 0, for: .scrollContent)
    }

    /// Bar buttons stay monochrome like the system apps; only a screen's primary action (a prominent
    /// glass button or a sheet's confirmation) carries the accent. Menus get the same through `CalendishMenuStyle`.
    func toolbarGlyph() -> some View {
        tint(nil)
    }

    /// Context menus take their item color from the tint where they're attached, which is basil app-wide,
    /// so the menu gets the same neutral rendering as `CalendishMenuStyle` while the row keeps basil.
    /// Destructive roles keep their red.
    func calendishContextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
        tint(CalendishStyle.accent).contextMenu(menuItems: menuItems).tint(nil)
    }

    func calendishContextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems, @ViewBuilder preview: () -> Preview
    ) -> some View {
        tint(CalendishStyle.accent).contextMenu(menuItems: menuItems, preview: preview).tint(nil)
    }
}

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

/// The app's only button chrome. Prominent buttons are the screen's primary action, drawn in the accent
/// with the on-accent label color.
struct GlassActionStyle: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if prominent { content.buttonStyle(.glassProminent).foregroundStyle(CalendishStyle.onAccent) }
        else { content.buttonStyle(.glass) }
    }
}

struct ServingsField: View {
    @Binding var servings: Int
    var body: some View {
        HStack {
            Text("Servings")
            Spacer()
            TextField("Servings", value: $servings, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(width: 60)
                .accessibilityLabel("Number of servings")
            Stepper("Adjust Servings", value: $servings, in: 1...1000)
                .labelsHidden()
                .fixedSize()
        }
        .onChange(of: servings) { _, value in servings = min(1000, max(1, value)) }
    }
}

/// Keeps clean sheets swipe-dismissible and confirms attempts to discard an edited sheet.
struct DraftDismissalGuard: UIViewRepresentable {
    let isDirty: Bool
    let onAttempt: () -> Void
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.isDirty = isDirty
        context.coordinator.onAttempt = onAttempt
        DispatchQueue.main.async {
            // Resolve the sheet containing this view, never a dialog it presents.
            var responder: UIResponder? = view
            while let current = responder, !(current is UIViewController) { responder = current.next }
            var controller = responder as? UIViewController
            while let current = controller {
                if current.presentingViewController != nil {
                    current.presentationController?.delegate = context.coordinator
                    break
                }
                controller = current.parent
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDirty = false
        var onAttempt: () -> Void = {}
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { !isDirty }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { onAttempt() }
    }
}
