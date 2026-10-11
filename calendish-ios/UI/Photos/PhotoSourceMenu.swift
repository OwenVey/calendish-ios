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
    @State private var fileURL: URL?
    @State private var loading = false
    @State private var errorMessage: String?

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
        .disabled(loading)
        .task(id: libraryItem) {
            guard let item = libraryItem else { return }
            loading = true
            defer { loading = false; libraryItem = nil }
            do {
                guard let picked = try await item.loadTransferable(type: PickedImage.self) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try Task.checkCancellation()
                onPick(picked.image)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Couldn’t load the photo. Choose the photo again, or try another photo."
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): fileURL = url
            case .failure:
                errorMessage = "Couldn’t open the photo. Choose the file again, or try another photo."
            }
        }
        .task(id: fileURL) {
            guard let url = fileURL else { return }
            loading = true
            defer { loading = false; fileURL = nil }
            do {
                let data = try await ImportFileReader.shared.read(url)
                guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                try Task.checkCancellation()
                onPick(image)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Couldn’t open the photo. Choose the file again, or try another photo."
            }
        }
        .calendishAlert("Couldn’t add photo", item: $errorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { Text($0) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onCapture: onPick).ignoresSafeArea()
        }
    }
}
