#if DEBUG
import Foundation

/// Compiled out of Release archives. Enabled only by an explicit UI-test launch flag.
final class FixtureNetwork: URLProtocol, @unchecked Sendable {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--mono-ui-fixtures") }
    static let fixtureHost = "fixtures.mono.example"
    static func accepts(_ url: URL) -> Bool { active && url.host == fixtureHost }
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAFElEQVR4nGNsaGhgAAMmCMXAwAAAGzwBhC8efmgAAAAASUVORK5CYII=") ?? Data()
    override class func canInit(with request: URLRequest) -> Bool { request.url.map(accepts) ?? false }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png", "Content-Length": String(Self.png.count)]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.httpMethod != "HEAD" { client?.urlProtocol(self, didLoad: Self.png) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
