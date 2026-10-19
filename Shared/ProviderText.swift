import Foundation

/// Request a concrete object class: loadItem may instead supply a temporary file URL.
@MainActor
enum ProviderText {
    static func load(_ provider: NSItemProvider) async throws -> String? {
        if provider.canLoadObject(ofClass: NSString.self) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: NSString.self) { object, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: object as? String) }
                }
            }
        }
        if provider.canLoadObject(ofClass: NSURL.self) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: NSURL.self) { object, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (object as? URL)?.absoluteString) }
                }
            }
        }
        return nil
    }
}
