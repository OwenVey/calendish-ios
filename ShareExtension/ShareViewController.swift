import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    /// The most useful thing shared: a PDF or images over the link to the page they came from, and a link over plain text.
    private static func item(from providers: [NSItemProvider]) async throws -> SharedInbox.Item {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) {
            return .pdf(try await data(from: provider, type: .pdf))
        }
        let imageProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        if !imageProviders.isEmpty {
            var images: [Data] = []
            for provider in imageProviders.prefix(10) { images.append(try await data(from: provider, type: .image)) }
            return .images(images)
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
            if let url = (item as? URL) ?? (item as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return .link(url)
            }
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }),
           let text = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            // Some apps share a link as plain text.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .link(url) }
            return .text(text)
        }
        throw CocoaError(.featureUnsupported)
    }

    private static func data(from provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
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
