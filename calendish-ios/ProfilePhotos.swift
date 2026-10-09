import PhotosUI
import SwiftUI
import ImageIO
import Supabase

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

struct ProfilePhotoControl: View {
    @Environment(HouseholdStore.self) private var store
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var selection: PhotosPickerItem?
    @State private var draft: ProfilePhotoDraft?
    @State private var working = false
    @State private var error: String?
    private var hasPhoto: Bool {
        guard let url = store.currentMember?.avatarURL else { return false }
        return url != ProfilePhotos.removedReference
    }

    var body: some View {
        VStack(spacing: 4) {
            Menu {
                Button("Choose a photo", systemImage: "photo.on.rectangle") { showLibrary = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo", systemImage: "camera") { showCamera = true }
                }
                if hasPhoto {
                    Button("Remove photo", systemImage: "trash", role: .destructive) {
                        working = true
                        error = nil
                        Task {
                            defer { working = false }
                            do { try await store.setProfilePhoto(nil) }
                            catch { self.error = InterfaceCopy.failure(error, action: "confirm photo removal", recovery: "Check your profile photo before trying again.") }
                        }
                    }
                }
            } label: {
                MemberAvatar(member: store.currentMember, size: 88)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: hasPhoto ? "pencil" : "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CalendishStyle.onAccent)
                            .frame(width: 26, height: 26)
                            .background(CalendishStyle.accent, in: .circle)
                            .overlay {
                                Circle().strokeBorder(Color(uiColor: .systemGroupedBackground), lineWidth: 2)
                            }
                            .accessibilityHidden(true)
                    }
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(hasPhoto ? "Change profile photo" : "Add profile photo")
            .accessibilityHint("Choose a photo or take one with the camera")
            .disabled(working)
            if working { ProgressView("Updating photo…").font(.footnote) }
            if let error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
        .photosPicker(isPresented: $showLibrary, selection: $selection, matching: .images, preferredItemEncoding: .compatible)
        .task(id: selection) {
            guard let selection else { return }
            working = true
            error = nil
            defer { working = false }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048
                      ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                try Task.checkCancellation()
                draft = ProfilePhotoDraft(image: UIImage(cgImage: cgImage))
                self.selection = nil
            } catch is CancellationError { }
            catch { self.error = InterfaceCopy.failure(error, action: "load the photo", recovery: "Choose the photo again.") }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let captured { draft = ProfilePhotoDraft(image: captured); self.captured = nil }
        }) {
            CameraPicker { captured = $0 }.ignoresSafeArea()
        }
        .sheet(item: $draft) { ProfilePhotoEditor(draft: $0) }
    }
    @State private var captured: UIImage?
}

private struct ProfilePhotoDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The circle previews exactly the square crop saved to Storage, including orientation.
private struct ProfilePhotoEditor: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let draft: ProfilePhotoDraft
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @GestureState private var translation = CGSize.zero
    @State private var working = false
    @State private var error: String?

    private func boundedOffset(side: CGFloat, proposed: CGSize? = nil) -> CGSize {
        let scale = side / min(draft.image.size.width, draft.image.size.height) * zoom
        let x = max(0, (draft.image.size.width * scale - side) / 2)
        let y = max(0, (draft.image.size.height * scale - side) / 2)
        let position = proposed ?? CGSize(width: offset.width + translation.width, height: offset.height + translation.height)
        return CGSize(width: min(x, max(-x, position.width)),
                      height: min(y, max(-y, position.height)))
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let side = min(geometry.size.width - 48, 300)
                ScrollView {
                    VStack(spacing: 24) {
                        Color.clear.frame(width: side, height: side)
                            .overlay {
                                Image(uiImage: draft.image).resizable().scaledToFill()
                                    .frame(width: side, height: side)
                                    .scaleEffect(zoom)
                                    .offset(boundedOffset(side: side))
                            }
                            .clipShape(.circle)
                            .contentShape(.circle)
                            .gesture(DragGesture().updating($translation) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    offset = boundedOffset(side: side, proposed: CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height))
                                })
                            .accessibilityLabel("Profile photo preview")
                            .accessibilityHint("Use the movement actions to position your photo")
                            .accessibilityAction(named: "Move photo left") { offset = boundedOffset(side: side, proposed: CGSize(width: offset.width - 20, height: offset.height)) }
                            .accessibilityAction(named: "Move photo right") { offset = boundedOffset(side: side, proposed: CGSize(width: offset.width + 20, height: offset.height)) }
                            .accessibilityAction(named: "Move photo up") { offset = boundedOffset(side: side, proposed: CGSize(width: offset.width, height: offset.height - 20)) }
                            .accessibilityAction(named: "Move photo down") { offset = boundedOffset(side: side, proposed: CGSize(width: offset.width, height: offset.height + 20)) }
                        Text("Drag to position your photo.").foregroundStyle(.secondary)
                        Slider(value: $zoom, in: 1...3) {
                            Text("Photo zoom")
                        } minimumValueLabel: {
                            Image(systemName: "minus.magnifyingglass")
                        } maximumValueLabel: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .onChange(of: zoom) { _, _ in offset = boundedOffset(side: side) }
                        .accessibilityValue("\(Int(zoom * 100)) percent")
                        if working { ProgressView("Saving photo…") }
                        if let error { Text(error).font(.callout).foregroundStyle(.red) }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .disabled(working)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(working)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use photo") {
                            let position = boundedOffset(side: side)
                            let scale = 512 / min(draft.image.size.width, draft.image.size.height) * zoom
                            let size = CGSize(width: draft.image.size.width * scale, height: draft.image.size.height * scale)
                            let format = UIGraphicsImageRendererFormat.default()
                            format.scale = 1
                            format.opaque = true
                            let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
                                draft.image.draw(in: CGRect(x: (512 - size.width) / 2 + position.width * 512 / side,
                                                           y: (512 - size.height) / 2 + position.height * 512 / side,
                                                           width: size.width, height: size.height))
                            }
                            working = true
                            error = nil
                            Task {
                                defer { working = false }
                                do { try await store.setProfilePhoto(image); dismiss() }
                                catch { self.error = InterfaceCopy.failure(error, action: "confirm the photo save", recovery: "Check your profile photo before trying again.") }
                            }
                        }
                        .disabled(working)
                    }
                }
            }
            .navigationTitle("Profile photo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(working)
    }
}
