import Foundation
import UIKit

/// Live Activities can't fetch photos themselves. Share only a small, local thumbnail.
enum CookingActivityPhoto {
    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.owenvey.calendish-ios")?
            .appending(path: "CookingActivityPhotos", directoryHint: .isDirectory)
    }

    static func image(named name: String?) -> UIImage? {
        guard let name, let id = UUID(uuidString: name), let directory else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: "\(id.uuidString).jpg").path)
    }

    static func save(_ image: UIImage, for sessionID: UUID) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A square crop at 3x for a 24-point thumbnail, with extra resolution for StandBy.
        let side: CGFloat = 144
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = side / min(image.size.width, image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                width: size.width, height: size.height))
        }
        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else { return }
        try data.write(to: directory.appending(path: "\(sessionID.uuidString).jpg"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func prune(keeping sessionID: UUID) {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent != "\(sessionID.uuidString).jpg" { try? FileManager.default.removeItem(at: file) }
    }

    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
