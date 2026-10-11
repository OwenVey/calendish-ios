import PhotosUI
import SafariServices
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct RecipeSourceBrowser: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { dismiss() }
    }
}
