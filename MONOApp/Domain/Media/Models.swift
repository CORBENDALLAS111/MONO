import Foundation
import CryptoKit

enum MediaKind: String, Codable, CaseIterable, Sendable { case video, image }
struct MediaVariant: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let mimeType: String
    var width: Int?
    var height: Int?
    var bytes: Int64?
    var fps: Double?
    var codec: String?
    var hasAudio: Bool?
    var quality: String {
        if let height { return "\(height)p" }
        return String(localized: "original")
    }
    static func best(_ variants: [Self], smaller: Bool = false) -> Self? {
        let ranked = variants.sorted {
            let a = Int64($0.width ?? 0) * Int64($0.height ?? 0)
            let b = Int64($1.width ?? 0) * Int64($1.height ?? 0)
            if a != b { return a > b }
            if $0.bytes != $1.bytes { return ($0.bytes ?? 0) > ($1.bytes ?? 0) }
            return $0.id < $1.id
        }
        return smaller ? ranked.last : ranked.first
    }
}
struct MediaAsset: Codable, Identifiable, Sendable {
    let id: String
    let kind: MediaKind
    let variants: [MediaVariant]
    var duration: Double?
}
struct MediaManifest: Codable, Identifiable, Sendable {
    let id: String
    let sourceURL: URL
    let title: String
    var creator: String?
    let resolver: String
    let assets: [MediaAsset]
}
enum JobState: String, Codable, Sendable {
    case waiting, running, paused, processing, completed, failed, canceled
    func allows(_ next: Self) -> Bool {
        switch (self, next) {
        case (.waiting, .running), (.waiting, .canceled), (.running, .paused),
             (.running, .processing), (.running, .failed), (.running, .canceled),
             (.paused, .waiting), (.paused, .canceled), (.failed, .waiting),
             (.failed, .canceled), (.processing, .completed), (.processing, .failed): true
        default: false
        }
    }
}
struct DownloadPreset: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var smaller = false
    var photosOnly = false
    var wifiOnly = false
    var saveToPhotos = false
    static var defaults: [Self] {
        [Self(name: String(localized: "preset.best")), Self(name: String(localized: "preset.small"), smaller: true), Self(name: String(localized: "preset.photos"), photosOnly: true)]
    }
}
struct DownloadJob: Codable, Identifiable, Sendable {
    var id = UUID()
    let sourceURL: URL
    let variant: MediaVariant
    let kind: MediaKind
    var name: String
    var folder: String
    var preset: DownloadPreset
    var state: JobState = .waiting
    var received: Int64 = 0
    var total: Int64?
    var speed: Double = 0
    var created = Date()
    var message: String?
    var file: String?
    var digest: String?
    var favorite = false
    var metadata: LocalMediaMetadata?
    var progress: Double? { guard let total, total > 0 else { return nil }; return min(1, Double(received) / Double(total)) }
    var eta: Double? { guard let total, speed > 0 else { return nil }; return max(0, Double(total - received) / speed) }
}
struct LocalMediaMetadata: Codable, Sendable {
    var width: Int?
    var height: Int?
    var duration: Double?
    var fps: Double?
    var codec: String?
    var hasAudio: Bool?
}
enum FileNames {
    static func safe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-"))
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter { allowed.contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "MONO" : String(cleaned.prefix(100))
    }
    static func identity(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
