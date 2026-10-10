import SwiftUI

/// Keeps clean sheets swipe-dismissible and confirms attempts to discard an edited sheet.
struct DraftDismissalGuard: UIViewRepresentable {
    let isDirty: Bool
    let onAttempt: () -> Void
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.isDirty = isDirty
        context.coordinator.onAttempt = onAttempt
        Task {
            // Resolve the sheet containing this view, never a dialog it presents.
            var responder: UIResponder? = view
            while let current = responder, !(current is UIViewController) { responder = current.next }
            var controller = responder as? UIViewController
            while let current = controller {
                if current.presentingViewController != nil {
                    current.presentationController?.delegate = context.coordinator
                    break
                }
                controller = current.parent
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDirty = false
        var onAttempt: () -> Void = {}
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { !isDirty }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { onAttempt() }
    }
}
