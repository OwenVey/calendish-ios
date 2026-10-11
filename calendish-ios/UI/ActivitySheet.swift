import SwiftUI

/// The system share sheet, for items prepared only once the person asks to share, such as a freshly rendered image.
struct ActivitySheet: UIViewControllerRepresentable {
    struct Items: Identifiable {
        let id = UUID()
        let values: [Any]
    }

    @Environment(\.dismiss) private var dismiss
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Finishing or cancelling only ends the activity, so close the sheet hosting it too.
        controller.completionWithItemsHandler = { _, _, _, _ in dismiss() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
