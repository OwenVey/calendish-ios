import SwiftUI

/// The circle previews exactly the square crop saved to Storage, including orientation.
struct ProfilePhotoEditor: View {
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
                        Button("Use photo") { save(side: side) }
                            .disabled(working)
                    }
                }
            }
            .navigationTitle("Profile photo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(working)
    }

    private func save(side: CGFloat) {
        let image = draft.cropped(zoom: zoom, offset: boundedOffset(side: side), side: side)
        working = true
        error = nil
        Task {
            defer { working = false }
            do { try await store.setProfilePhoto(image); dismiss() }
            catch { self.error = InterfaceCopy.failure(error, action: "confirm the photo save", recovery: "Check your profile photo before trying again.") }
        }
    }
}
