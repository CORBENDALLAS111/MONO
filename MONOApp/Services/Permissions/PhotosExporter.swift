import Foundation
import Photos
import AVFoundation
import UIKit

enum PhotosExporter {
    @MainActor static func save(_ url: URL, kind: MediaKind) async throws {
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined,
           UIApplication.shared.applicationState != .active { throw CocoaError(.fileWriteNoPermission) }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CocoaError(.fileWriteNoPermission) }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: kind == .video ? .video : .photo, fileURL: url, options: nil)
        }
    }
}
