import PhotosUI
import SwiftUI
import ImageIO
import Supabase

struct ProfilePhotoDraft: Identifiable {
    let id = UUID()
    let image: UIImage

    /// The 512-pixel square the editor's circle previews, given the zoom and the offset within a `side`-point circle.
    func cropped(zoom: Double, offset: CGSize, side: CGFloat) -> UIImage {
        let scale = 512 / min(image.size.width, image.size.height) * zoom
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
            image.draw(in: CGRect(x: (512 - size.width) / 2 + offset.width * 512 / side,
                                  y: (512 - size.height) / 2 + offset.height * 512 / side,
                                  width: size.width, height: size.height))
        }
    }
}
