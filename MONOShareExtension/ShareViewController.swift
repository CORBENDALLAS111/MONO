import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        show(String(localized: "share.reading"), done: false)
        Task { await receive() }
    }
    private func receive() async {
        do {
            guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { throw InputError.invalidURL }
            var accepted: [URL] = []
            for item in items {
                for provider in (item.attachments ?? []).prefix(10) {
                    let loadedText = try await ProviderText.load(provider)
                    if let loadedText { accepted.append(try URLPolicy.extract(loadedText)) }
                }
            }
            guard !accepted.isEmpty, accepted.count <= 10 else { throw InputError.invalidURL }
            for url in Set(accepted) { try ShareInbox.write(url) }
            show(String(localized: "share.pending"), done: true)
        } catch {
            show(String(localized: "share.failure"), done: true)
        }
    }
    private func show(_ message: String, done: Bool) {
        for child in children { child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        let host = UIHostingController(rootView: ShareConfirmation(message: message, done: done) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareConfirmation: View {
    let message: String
    let done: Bool
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "MONO").font(.caption.weight(.bold)).tracking(5)
            Text(message).font(.title2.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            if done { Button("close", action: close).buttonStyle(.glass).tint(.primary) }
            else { ProgressView().tint(.primary) }
        }.padding(30).tint(.primary)
    }
}
