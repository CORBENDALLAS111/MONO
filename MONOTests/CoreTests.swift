import XCTest
@testable import MONO

final class CoreTests: XCTestCase {
    func testActivityLogIsBounded() {
        var log = ActivityLog(capacity: 2)
        log.append(.ready); log.append(.resolving); log.append(.completed)
        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries.first?.kind, .resolving)
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
    }
    func testActivityLogRedactsSecretsAndLinks() {
        var log = ActivityLog()
        log.append(.failed, detail: "https://example.com/private?token=secret Bearer abc123 token=private-value")
        log.append(.failed, detail: "Authorization: Bearer another-secret")
        XCTAssertFalse(log.exportText.contains("example.com"))
        XCTAssertFalse(log.exportText.contains("abc123"))
        XCTAssertFalse(log.exportText.contains("private-value"))
        XCTAssertFalse(log.exportText.contains("another-secret"))
    }
    func testNormalizeRemovesFragment() throws {
        XCTAssertEqual(try URLPolicy.normalize(" https://EXAMPLE.com/a.mp4#part ").absoluteString, "https://example.com/a.mp4")
    }
    func testRejectUnsafeSyntax() {
        for raw in ["http://example.com/a.mp4", "file:///a", "https://user:secret@example.com/a", "https://example.com:8443/a", "https://localhost/a", "https://printer.local/a", "https://example.com./a", "javascript:alert(1)"] {
            XCTAssertThrowsError(try URLPolicy.normalize(raw), raw)
        }
    }
    func testPrivateIPv4() {
        for ip in [UInt32(0x00000000),0x0a000001,0x7f000001,0xa9fe0001,0xac100001,0xc0a80001,0x64400001,0xe0000001] { XCTAssertFalse(URLPolicy.isPublicIPv4(ip)) }
        XCTAssertTrue(URLPolicy.isPublicIPv4(0x08080808))
    }
    func testTikTokShortLinkRecognition() throws {
        for host in ["vm.tiktok.com", "vt.tiktok.com", "www.tiktok.com"] {
            XCTAssertTrue(URLPolicy.isSocial(try URLPolicy.normalize("https://\(host)/abcdef/")))
        }
        XCTAssertFalse(URLPolicy.isSocial(try URLPolicy.normalize("https://tiktok.com.evil.example/a")))
    }
    func testSharedTextExtraction() throws {
        XCTAssertEqual(try URLPolicy.extract("My video https://vm.tiktok.com/abcdef/ here").host, "vm.tiktok.com")
    }
    func testSecureFilename() {
        XCTAssertEqual(FileNames.safe("../../ <file>|:??"), "file")
        XCTAssertEqual(FileNames.safe("../"), "MONO")
        XCTAssertEqual(FileNames.safe(String(repeating: "a", count: 200)).count, 100)
    }
    func testRankingUsesRealDimensions() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.mp4"))
        let low = MediaVariant(id: "4K-name-is-not-quality", url: url, mimeType: "video/mp4", width: 1280, height: 720, bytes: 100)
        let high = MediaVariant(id: "original", url: url, mimeType: "video/mp4", width: 1920, height: 1080, bytes: 200)
        XCTAssertEqual(MediaVariant.best([low,high])?.id, high.id)
        XCTAssertEqual(MediaVariant.best([low,high], smaller: true)?.id, low.id)
        XCTAssertNil(MediaVariant.best([]))
    }
    func testSmallerPreferenceUsesKnownFileSize() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.mp4"))
        let efficient = MediaVariant(id: "efficient", url: url, mimeType: "video/mp4", width: 1920, height: 1080, bytes: 100)
        let heavy = MediaVariant(id: "heavy", url: url, mimeType: "video/mp4", width: 1280, height: 720, bytes: 200)
        XCTAssertEqual(MediaVariant.best([heavy,efficient], smaller: true)?.id, efficient.id)
    }
    func testLocalAddressFailsBeforeTransfer() async throws {
        let url = try XCTUnwrap(URL(string: "https://127.0.0.1/a.jpg"))
        do { try await URLPolicy.validate(url); XCTFail("Private addresses must be rejected") }
        catch { XCTAssertEqual(error as? InputError, .unsafeHost) }
    }
    func testStoragePathConflictIsReported() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("regular file".utf8).write(to: path)
        XCTAssertThrowsError(try DiskStore(root: path))
    }
    func testStateMachine() {
        XCTAssertTrue(JobState.running.allows(.paused))
        XCTAssertTrue(JobState.paused.allows(.waiting))
        XCTAssertTrue(JobState.running.allows(.processing))
        XCTAssertFalse(JobState.running.allows(.completed))
        XCTAssertFalse(JobState.completed.allows(.running))
        XCTAssertFalse(JobState.canceled.allows(.completed))
    }
    func testUnknownProgressIsUnknown() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.mp4"))
        let job = DownloadJob(sourceURL: url, variant: MediaVariant(id: "one", url: url, mimeType: "video/mp4"), kind: .video, name: "One", folder: "Folder", preset: DownloadPreset(name: "Best"))
        XCTAssertNil(job.progress)
        XCTAssertNil(job.eta)
    }
    func testPresetRoundTrip() throws {
        let preset = DownloadPreset(name: "Best + Wi-Fi + Photos", wifiOnly: true, saveToPhotos: true)
        XCTAssertEqual(try JSONDecoder().decode(DownloadPreset.self, from: JSONEncoder().encode(preset)), preset)
    }
    func testPersistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = try DiskStore(root: dir)
        var snapshot = LibrarySnapshot()
        snapshot.consumedInbox.insert("abc")
        try disk.save(snapshot)
        XCTAssertEqual(try disk.load().presets, snapshot.presets)
        XCTAssertEqual(try disk.load().consumedInbox, ["abc"])
    }
    func testCorruptStorageIsNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = try DiskStore(root: dir)
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: disk.metadata)
        XCTAssertThrowsError(try disk.load())
        XCTAssertEqual(try Data(contentsOf: disk.metadata), corrupt)
    }
    func testInboxIdempotency() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try XCTUnwrap(URL(string: "https://example.com/a.jpg"))
        try ShareInbox.write(url, to: dir)
        try ShareInbox.write(url, to: dir)
        XCTAssertEqual(try ShareInbox.read(from: dir).count, 1)
    }
    func testSignatureRejectsHTML() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("<html>not media</html>".utf8).write(to: file)
        XCTAssertThrowsError(try FileVerifier.verify(file, mime: "image/jpeg"))
    }
    func testDuplicateFileHash() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var data = Data([137,80,78,71,13,10,26,10])
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: file)
        let a = try FileVerifier.verify(file, mime: "image/png")
        let b = try FileVerifier.verify(file, mime: "image/png")
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, 108)
    }
    func testSocialWithoutServiceIsExplicit() async throws {
        let url = try XCTUnwrap(URL(string: "https://vm.tiktok.com/abcdef/"))
        do {
            _ = try await ResolverRegistry(endpoint: "", token: "").resolve(url)
            XCTFail("Must not fabricate a media manifest")
        } catch { XCTAssertEqual(error as? InputError, .backendMissing) }
    }
}

