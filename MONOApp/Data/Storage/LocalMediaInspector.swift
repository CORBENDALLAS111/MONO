import Foundation
import AVFoundation
import ImageIO

enum LocalMediaInspector {
    static func inspect(_ url: URL, kind: MediaKind) async throws -> LocalMediaMetadata {
        if kind == .image {
            return try await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceGetCount(source) > 0,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 16384, height <= 16384 else { throw InputError.invalidFile }
                return LocalMediaMetadata(width: width, height: height)
            }.value
        }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw InputError.invalidFile }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frame = CGRect(origin: .zero, size: size).applying(transform)
        let rate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let descriptions = try await track.load(.formatDescriptions)
        let codec = descriptions.first.map { description in
            let value = CMFormatDescriptionGetMediaSubType(description)
            let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
            return String(bytes: bytes, encoding: .ascii) ?? ""
        }
        return LocalMediaMetadata(width: Int(abs(frame.width)), height: Int(abs(frame.height)),
                                  duration: duration.isFinite ? duration : nil,
                                  fps: Double(rate), codec: codec, hasAudio: !audio.isEmpty)
    }
}
