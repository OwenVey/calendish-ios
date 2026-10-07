import SwiftUI
import UIKit

/// The share sheet entry point. It saves what was shared to the inbox and closes; the app imports it next time it's open.
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
            do {
                try SharedInbox.save(try await Self.item(from: providers))
                status.state = .saved
                try? await Task.sleep(for: .seconds(1.5))
                finish()
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
    enum State { case saving, saved, failed }
    var state = State.saving
}

private struct ShareView: View {
    var status: ShareStatus
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch status.state {
            case .saving:
                ProgressView()
                Text("Saving to Calendish…").font(.headline)
            case .saved:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Saved to Calendish").font(.headline)
                Text("Open Calendish to review and save the recipe.").font(.subheadline).foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Couldn’t Save to Calendish").font(.headline)
                Text("Try sharing a link, text, photos, or a PDF.").font(.subheadline).foregroundStyle(.secondary)
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
