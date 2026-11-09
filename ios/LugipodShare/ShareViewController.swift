import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Share Extension behind "Share → לוגיפוד" (WhatsApp, Photos, Safari...). It receives a picture, shrinks it, shows where it can go (a
/// Lugichat conversation, or a question for a teacher before a lesson) and sends it. See ShareView.swift for the screen.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0xF6 / 255, green: 0xF7 / 255, blue: 0xFB / 255, alpha: 1)
        Task { await start() }
    }

    private func start() async {
        let providers = ((extensionContext?.inputItems as? [NSExtensionItem]) ?? []).flatMap { $0.attachments ?? [] }
        guard let picture = await Self.firstPicture(in: providers) else {
            let alert = UIAlertController(title: "אי אפשר לשתף את זה", message: "אפשר לשתף ללוגיפוד תמונה.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "סגירה", style: .default) { [weak self] _ in self?.close() })
            present(alert, animated: true)
            return
        }

        let model = ShareModel(image: picture.image, jpeg: picture.jpeg)
        let host = UIHostingController(rootView: ShareView(
            model: model,
            onClose: { [weak self] in self?.close() },
            onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        await model.load()
    }

    private func close() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    /// The first picture among the shared items, already shrunk. The system hands over a temporary file that disappears when the callback
    /// returns, so the picture is read inside it.
    private static func firstPicture(in providers: [NSItemProvider]) async -> (image: UIImage, jpeg: Data)? {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<(image: UIImage, jpeg: Data)?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                cont.resume(returning: ShareImage.prepare(url))
            }
        }
    }
}
