import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase
import VisionKit

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
