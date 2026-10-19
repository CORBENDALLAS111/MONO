import Foundation
import CryptoKit

struct InboxRequest: Codable, Identifiable, Sendable {
    let id: String
    let url: URL
    let created: Date
    init(url: URL) {
        self.url = url
        id = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        created = Date()
    }
}

enum ShareInbox {
    static func directory() throws -> URL {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MonoAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { throw CocoaError(.fileNoSuchFile) }
        let dir = container.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func write(_ url: URL, to directory: URL? = nil) throws {
        let dir = try directory ?? self.directory()
        let request = InboxRequest(url: try URLPolicy.normalize(url.absoluteString))
        try JSONEncoder().encode(request).write(to: dir.appendingPathComponent(request.id + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func read(from directory: URL? = nil) throws -> [(URL, InboxRequest)] {
        let dir = try directory ?? self.directory()
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0, try JSONDecoder().decode(InboxRequest.self, from: Data(contentsOf: $0))) }
    }
}
