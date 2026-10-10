import SwiftUI

/// The recipe's photo in the Live Activity, or a utensils symbol when it has none.
struct CookingActivityThumbnail: View {
    let imageName: String?
    let size: Double

    var body: some View {
        Group {
            if let image = CookingActivityPhoto.image(named: imageName) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
