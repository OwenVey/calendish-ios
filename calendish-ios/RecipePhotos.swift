import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase

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
        let load = Task { () -> UIImage? in
            var data = try? Data(contentsOf: file)
            if data == nil, let downloaded = try? await supabase.storage.from(Self.bucket).download(path: path) {
                guard !Task.isCancelled, generation == self.generation else { return nil }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? downloaded.write(to: file)
                data = downloaded
            }
            guard !Task.isCancelled, generation == self.generation, let data, let image = UIImage(data: data) else { return nil }
            let prepared = thumbnail
                ? await image.byPreparingThumbnail(ofSize: CGSize(width: 320, height: 320))
                : await image.byPreparingForDisplay()
            return prepared ?? image
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

    /// Saves a just-picked photo under its upload path so it shows before the upload finishes.
    func insert(_ data: Data, for path: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: path))
    }

    private func key(_ path: String, _ thumbnail: Bool) -> String { thumbnail ? "\(path)#thumbnail" : path }
    private func fileURL(for path: String) -> URL {
        directory.appending(path: path.replacingOccurrences(of: "/", with: "_"))
    }
}

/// A recipe photo that fills its frame, loading from the cache or the bucket.
struct RecipePhoto: View {
    let path: String
    var thumbnail = false
    @State private var loaded: (path: String, image: UIImage?)?
    private var image: UIImage? {
        loaded?.path == path ? loaded?.image : RecipePhotos.shared.cachedImage(for: path, thumbnail: thumbnail)
    }
    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if loaded?.path == path {
                    Image(systemName: "photo").font(thumbnail ? .title3 : .largeTitle).foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: path) {
                let image = await RecipePhotos.shared.image(for: path, thumbnail: thumbnail)
                loaded = (path, image)
            }
    }
}

/// The usual ways to add a photo: the camera, the photo library, Files, and the clipboard.
/// Wraps `label` in a menu of those choices, plus Remove Photo when there's one to remove.
struct PhotoSourceMenu<Label: View>: View {
    var hasPhoto: Bool
    var onPick: (UIImage) -> Void
    var onRemove: () -> Void
    @ViewBuilder var label: Label
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var libraryItem: PhotosPickerItem?

    var body: some View {
        Menu {
            Section {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo", systemImage: "camera") { showCamera = true }
                }
                Button("Choose from Library", systemImage: "photo.on.rectangle") { showLibrary = true }
                Button("Choose File", systemImage: "folder") { showFiles = true }
                if UIPasteboard.general.hasImages {
                    Button("Paste Photo", systemImage: "doc.on.clipboard") {
                        if let image = UIPasteboard.general.image { onPick(image) }
                    }
                }
            }
            if hasPhoto {
                Section {
                    Button("Remove Photo", systemImage: "trash", role: .destructive, action: onRemove)
                }
            }
        } label: { label }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task {
                if let picked = try? await item.loadTransferable(type: PickedImage.self) { onPick(picked.image) }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) { onPick(image) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onCapture: onPick).ignoresSafeArea()
        }
    }
}

/// An image loaded from the photo library, decoded from whatever format it was stored in.
nonisolated struct PickedImage: Transferable {
    let image: UIImage
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            return PickedImage(image: image)
        }
    }
}

/// The system camera. SwiftUI has no camera picker of its own.
private struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
