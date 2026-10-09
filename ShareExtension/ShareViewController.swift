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

@Observable
final class ShareStatus {
    enum State { case saving, saved, unsupported, failed }
    var state = State.saving
}

private struct ShareView: View {
    var status: ShareStatus
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch status.state {
            case .saving:
                ProgressView("Sending to Calendish…").font(.headline)
            case .saved:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Ready to import").font(.headline)
                Text("Open Calendish to review and save the recipe.").font(.subheadline).foregroundStyle(.secondary)
            case .unsupported, .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Couldn’t send to Calendish").font(.headline)
                Text(status.state == .unsupported
                    ? "Share a recipe link, recipe text, photos, or a PDF."
                    : "Open Calendish and try importing the recipe there.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if status.state != .saving {
                Button("Done", action: onDone).buttonStyle(.glass).padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: 340)
        .glassEffect(in: .rect(cornerRadius: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Color(red: 0.055, green: 0.624, blue: 0.431))
    }
}
