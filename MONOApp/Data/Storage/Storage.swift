import Foundation
import CryptoKit

struct LibrarySnapshot: Codable {
    var version = 1
    var jobs: [DownloadJob] = []
    var presets: [DownloadPreset] = DownloadPreset.defaults
    var consumedInbox: Set<String> = []
    var pendingInput: String?
}

struct DiskStore: Sendable {
    let root: URL
    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("MONO", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var directory = self.root
        try directory.setResourceValues(excluded)
    }
    var metadata: URL { root.appendingPathComponent("library-v1.json") }
    func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: metadata.path) else { return LibrarySnapshot() }
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: metadata))
        guard snapshot.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return snapshot
    }
    func save(_ snapshot: LibrarySnapshot) throws {
        try JSONEncoder().encode(snapshot).write(to: metadata, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func file(_ name: String) -> URL { root.appendingPathComponent(name) }
    func resumeFile(_ id: UUID) -> URL { file(id.uuidString + ".resume") }
}

enum FileVerifier {
    static let maximumBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let extensions = ["video/mp4": "mp4", "video/quicktime": "mov", "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp", "image/heic": "heic", "image/heif": "heif"]
    static func verify(_ file: URL, mime: String) throws -> (String, Int64) {
        guard extensions[mime] != nil else { throw InputError.invalidFile }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 32) ?? Data()
        let b = [UInt8](header)
        let ftyp = b.count >= 12 && String(bytes: b[4..<8], encoding: .ascii) == "ftyp"
        let matches: Bool
        switch mime {
        case "video/mp4", "video/quicktime", "image/heic", "image/heif": matches = ftyp
        case "image/jpeg": matches = b.starts(with: [0xff, 0xd8, 0xff])
        case "image/png": matches = b.starts(with: [137,80,78,71,13,10,26,10])
        case "image/gif": matches = b.starts(with: Array("GIF8".utf8))
        case "image/webp": matches = b.count >= 12 && String(bytes: b[0..<4], encoding: .ascii) == "RIFF" && String(bytes: b[8..<12], encoding: .ascii) == "WEBP"
        default: matches = false
        }
        guard matches else { throw InputError.invalidFile }
        try handle.seek(toOffset: 0)
        var hasher = SHA256(), size: Int64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            size += Int64(chunk.count)
            guard size <= maximumBytes else { throw InputError.limit }
            hasher.update(data: chunk)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
}
