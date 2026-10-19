import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// SwiftUI PasteButton retains an internal rectangular fill. UIKit's documented
/// configuration removes that rectangle using a capsule matching the system surface,
/// inside native Liquid Glass, without reading/polling UIPasteboard.
struct NativePasteControl: UIViewRepresentable {
    let receive: @MainActor (String?) -> Void
    func makeUIView(context: Context) -> PasteTargetView { PasteTargetView(receive: receive) }
    func updateUIView(_ view: PasteTargetView, context: Context) {
        view.receive = receive
        view.isUserInteractionEnabled = context.environment.isEnabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PasteTargetView, context: Context) -> CGSize? {
        let intrinsic = uiView.control.intrinsicContentSize
        return CGSize(width: proposal.width ?? max(120, intrinsic.width), height: max(48, intrinsic.height))
    }
}

@MainActor
final class PasteTargetView: UIView {
    let control: UIPasteControl
    var receive: @MainActor (String?) -> Void
    init(receive: @escaping @MainActor (String?) -> Void) {
        self.receive = receive
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.cornerStyle = .capsule
        // UIPasteControl renders the RGB of a clear base as black in light mode.
        // A dynamic opaque system color preserves contrast in both appearances.
        configuration.baseBackgroundColor = .systemBackground
        configuration.baseForegroundColor = .label
        control = UIPasteControl(configuration: configuration)
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.url.identifier, UTType.plainText.identifier])
        control.target = self
        control.backgroundColor = .clear
        control.accessibilityLabel = String(localized: "paste")
        control.accessibilityIdentifier = "pasteButton"
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor), control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor), control.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { return nil }
    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first else { receive(nil); return }
        Task { [weak self] in
            do { self?.receive(try await ProviderText.load(provider)) }
            catch { self?.receive(nil) }
        }
    }
}
