import SwiftUI
import ImageIO
import AVFoundation

enum ThumbnailDecoder {
    static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }
}

struct LocalThumbnail: View {
    let url: URL?
    let kind: MediaKind
    @State private var image: CGImage?
    var body: some View {
        ZStack {
            Rectangle().fill(.primary.opacity(0.04))
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            else { AppIcon(token: kind == .video ? .video : .image, size: 30).foregroundStyle(.secondary) }
        }.frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: url) {
            guard let url else { return }
            do {
                if kind == .image {
                    image = try await Task.detached(priority: .utility) {
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        return ThumbnailDecoder.image(data)
                    }.value
                } else {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 600, height: 600)
                    let result = try await generator.image(at: .zero)
                    if !Task.isCancelled { image = result.image }
                }
            } catch { image = nil } // Preview is optional; the saved file remains accessible via Quick Look.
        }.accessibilityHidden(true)
    }
}

struct RemoteImagePreview: View {
    let variant: MediaVariant
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 220) }
        }.task(id: variant.url) {
            do {
                guard variant.mimeType.hasPrefix("image/"), (variant.bytes ?? 0) <= 8 * 1024 * 1024 else { return }
                let (data, response) = try await SafeHTTP().bounded(URLRequest(url: variant.url), limit: 8 * 1024 * 1024)
                guard response.mimeType == variant.mimeType else { return }
                let decoded = await Task.detached(priority: .utility) { ThumbnailDecoder.image(data) }.value
                if !Task.isCancelled { image = decoded }
            } catch { image = nil }
        }.accessibilityHidden(true)
    }
}
