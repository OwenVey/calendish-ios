import ImageIO
import PhotosUI
import Supabase
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Downloads recipe photos from the private `recipe-images` bucket and caches them in memory and on disk.
/// Every upload gets a new path, so a cached copy never goes stale.
final class RecipePhotos {
    static let shared = RecipePhotos()
    static let bucket = "recipe-images"

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var generation = UUID()
    private var loads: [String: Task<UIImage?, Never>] = [:]
    private let directory = URL.cachesDirectory.appending(path: "RecipePhotos", directoryHint: .isDirectory)

    /// Private household photos must not survive an account change on this device.
    func clearCache() {
        generation = UUID()
        for load in loads.values { load.cancel() }
        loads.removeAll()
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Shrinks a photo to a sensible size for the app and encodes it as JPEG.
    static func uploadData(for image: UIImage) -> Data? {
        let longestSide: CGFloat = 1600
        let scale = min(1, longestSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // Drawing also bakes in the orientation, so camera photos come out upright everywhere.
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    func cachedImage(for path: String, thumbnail: Bool) -> UIImage? {
        memory.object(forKey: key(path, thumbnail) as NSString)
    }

    func image(for path: String, thumbnail: Bool) async -> UIImage? {
        let key = key(path, thumbnail)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let load = loads[key] { return await load.value }
        let generation = generation
        let file = fileURL(for: path)
        let thumbnailFile = thumbnail ? thumbnailURL(for: path) : nil
        let directory = directory
        let load = Task { () -> UIImage? in
            if let image = await Self.prepared(file: file, thumbnail: thumbnailFile) { return image }
            guard let downloaded = try? await supabase.storage.from(Self.bucket).download(path: path),
                  !Task.isCancelled, generation == self.generation else { return nil }
            return await Self.prepared(downloaded: downloaded, directory: directory, file: file, thumbnail: thumbnailFile)
        }
        loads[key] = load
        let image = await load.value
        guard generation == self.generation else { return nil }
        loads[key] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: key as NSString, cost: cost)
        }
        return image
    }

    /// Loads thumbnails ahead of scrolling, a few at a time, so rows show their photos right away.
    func prefetchThumbnails(for paths: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for (index, path) in paths.enumerated() {
                if index >= 4 { await group.next() }
                group.addTask { _ = await self.image(for: path, thumbnail: true) }
            }
        }
    }

    /// Saves a just-picked photo under its upload path so it shows before the upload finishes.
    func insert(_ data: Data, for path: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: path))
    }

    private func key(_ path: String, _ thumbnail: Bool) -> String { thumbnail ? "\(path)#thumbnail" : path }
    private func fileURL(for path: String) -> URL {
        directory.appending(path: path.replacingOccurrences(of: "/", with: "_"))
    }
    private func thumbnailURL(for path: String) -> URL {
        directory.appending(path: path.replacingOccurrences(of: "/", with: "_") + ".thumbnail")
    }

    /// Reads and decodes a cached photo off the main thread, preferring its small thumbnail copy.
    private nonisolated static func prepared(file: URL, thumbnail: URL?) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            if let thumbnail, let data = try? Data(contentsOf: thumbnail), let image = UIImage(data: data) {
                return image.preparingForDisplay() ?? image
            }
            guard let data = try? Data(contentsOf: file) else { return nil }
            return decoded(data, thumbnail: thumbnail)
        }.value
    }

    /// Saves a downloaded photo, then decodes it off the main thread.
    private nonisolated static func prepared(downloaded: Data, directory: URL, file: URL, thumbnail: URL?) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? downloaded.write(to: file)
            return decoded(downloaded, thumbnail: thumbnail)
        }.value
    }

    /// Thumbnails fill a grid card at 3x and are saved small, so later launches skip decoding the full photo.
    /// ImageIO downsamples straight from the file data, so the full photo is never decoded in memory.
    private nonisolated static func decoded(_ data: Data, thumbnail: URL?) -> UIImage? {
        guard let thumbnail else {
            guard let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              min(width, height) > 0 else { return nil }
        // ImageIO limits the longest side, so scale it to give the shortest side 540 pixels.
        let shortestSide: CGFloat = 540
        let longestSide = min(max(width, height), (shortestSide * max(width, height) / min(width, height)).rounded())
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let small = UIImage(cgImage: cgImage)
        if let jpeg = small.jpegData(compressionQuality: 0.8) { try? jpeg.write(to: thumbnail) }
        return small
    }
}
