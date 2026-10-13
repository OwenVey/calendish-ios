import SwiftUI

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
                    ProgressView().tint(.secondary)
                }
            }
            .clipped()
            .task(id: path) {
                let image = await RecipePhotos.shared.image(for: path, thumbnail: thumbnail)
                loaded = (path, image)
            }
    }
}
