import ImageIO
import PhotosUI
import Supabase
import SwiftUI

/// Private avatar references remain stable across household moves. A fresh path avoids stale caches.
final class ProfilePhotos {
    static let shared = ProfilePhotos()
    static let bucket = "profile-photos"
    static let removedReference = URL(string: "calendish-avatar:removed")!
    private var images: [URL: UIImage] = [:]
    private var generation = UUID()

    static func reference(path: String) -> URL { URL(string: "calendish-avatar:///\(path)")! }
    static func path(for url: URL?) -> String? {
        guard let url, url.scheme == "calendish-avatar", url != removedReference else { return nil }
        return String(url.path.dropFirst())
    }
    func insert(_ image: UIImage, for url: URL) { images[url] = image }
    func clearCache() { generation = UUID(); images.removeAll() }
    func image(for url: URL) async -> UIImage? {
        if let image = images[url] { return image }
        let generation = generation
        guard let path = Self.path(for: url),
              let data = try? await supabase.storage.from(Self.bucket).download(path: path),
              let image = UIImage(data: data), generation == self.generation, !Task.isCancelled else { return nil }
        images[url] = image
        return image
    }
}
