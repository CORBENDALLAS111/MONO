import Foundation
import Photos
import AVFoundation

enum PhotosExporter {
    static func save(_ url: URL, kind: MediaKind) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CocoaError(.fileWriteNoPermission) }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: kind == .video ? .video : .photo, fileURL: url, options: nil)
        }
    }
}
