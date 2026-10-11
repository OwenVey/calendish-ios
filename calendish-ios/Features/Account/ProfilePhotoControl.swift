import ImageIO
import PhotosUI
import SwiftUI

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
                        kCGImageSourceThumbnailMaxPixelSize: 2048,
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
