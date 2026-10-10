import SwiftUI

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
