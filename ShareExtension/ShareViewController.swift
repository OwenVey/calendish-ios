import SwiftUI
import UIKit

/// Saves shared source material to the inbox; the app imports it next time it's open.
final class ShareViewController: UIViewController {
    private let status = ShareStatus()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(status: status) { [weak self] in self?.finish() })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task {
            let item: RecipeImport
            do {
                item = try await Self.item(from: providers)
            } catch {
                status.state = .unsupported
                return
            }
            do {
                try SharedInbox.save(item)
                status.state = .saved
            } catch {
                status.state = .failed
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Loads each attachment the same way the app loads pasted and dropped content, then keeps the most useful.
    private static func item(from providers: [NSItemProvider]) async throws -> RecipeImport {
        var items: [RecipeImport] = []
        for provider in providers {
            if let item = try? await load(provider) { items.append(item) }
        }
        guard let item = RecipeImport.combined(items) else { throw CocoaError(.featureUnsupported) }
        return item
    }

    private static func load(_ provider: NSItemProvider) async throws -> RecipeImport {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: RecipeImport.self) { continuation.resume(with: $0) }
        }
    }
}
