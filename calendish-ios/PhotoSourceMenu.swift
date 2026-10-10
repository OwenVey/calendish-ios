import SwiftUI
import PhotosUI

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
                    Button("Take photo", systemImage: "camera") { showCamera = true }
                }
                Button("Choose a photo", systemImage: "photo.on.rectangle") { showLibrary = true }
                Button("Choose file", systemImage: "folder") { showFiles = true }
                if UIPasteboard.general.hasImages {
                    Button("Paste photo", systemImage: "doc.on.clipboard") {
                        if let image = UIPasteboard.general.image { onPick(image) }
                    }
                }
            }
            if hasPhoto {
                Section {
                    Button("Remove photo", systemImage: "trash", role: .destructive, action: onRemove)
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
