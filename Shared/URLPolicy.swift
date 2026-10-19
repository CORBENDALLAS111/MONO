import Foundation
import Darwin

enum InputError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL, unsafeHost, unsupported, backendMissing, invalidManifest, http(Int), invalidFile, limit
    var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "error.url")
        case .unsafeHost: String(localized: "error.host")
        case .unsupported: String(localized: "error.unsupported")
        case .backendMissing: String(localized: "error.backend")
        case .invalidManifest: String(localized: "error.manifest")
        case .http(let status): String(localized: "error.http") + " (\(status))"
        case .invalidFile: String(localized: "error.file")
        case .limit: String(localized: "error.limit")
        }
    }
}

enum URLPolicy {
    static func normalize(_ text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 8192,
              var c = URLComponents(string: trimmed), c.scheme?.lowercased() == "https",
              let host = c.host?.lowercased(), !host.isEmpty,
              c.user == nil, c.password == nil, c.port == nil || c.port == 443,
              !host.hasSuffix("."), host.contains("."),
              !["localhost", "local", "internal", "home", "test", "invalid"].contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { throw InputError.invalidURL }
        c.host = host
        c.scheme = "https"
        c.fragment = nil
        guard let url = c.url else { throw InputError.invalidURL }
        return url
    }

    static func isPublicIPv4(_ value: UInt32) -> Bool {
        let a = value >> 24, b = (value >> 16) & 255
        return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
            (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254) ||
            (a == 172 && (16...31).contains(b)) || (a == 192 && [0, 168].contains(b)) ||
            (a == 198 && [18, 19, 51].contains(b)) || (a == 203 && b == 0))
    }

    static func validate(_ url: URL) async throws {
        let normalized = try normalize(url.absoluteString)
        #if DEBUG
        if FixtureNetwork.accepts(normalized) { return }
        #endif
        guard let host = normalized.host else { throw InputError.invalidURL }
        try await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, "443", &hints, &result) == 0, let first = result else {
                throw InputError.unsafeHost
            }
            defer { freeaddrinfo(first) }
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let p = cursor {
                let info = p.pointee
                guard let address = info.ai_addr else { throw InputError.unsafeHost }
                if info.ai_family == AF_INET {
                    let value = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
                    guard isPublicIPv4(value) else { throw InputError.unsafeHost }
                } else if info.ai_family == AF_INET6 {
                    var ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                    let bytes = withUnsafeBytes(of: &ip) { Array($0) }
                    // Only globally routable unicast; exclude documentation and Teredo ranges.
                    guard bytes[0] & 0xe0 == 0x20,
                          !(bytes[0] == 0x20 && bytes[1] == 0x02),
                          !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 2),
                          !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8),
                          !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0 && bytes[3] == 0)
                    else { throw InputError.unsafeHost }
                } else { throw InputError.unsafeHost }
                cursor = info.ai_next
            }
        }.value
    }

    static func isSocial(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return ["tiktok.com", "instagram.com", "youtube.com", "youtu.be", "twitter.com", "x.com", "reddit.com", "redd.it", "pinterest.com", "pin.it", "facebook.com", "fb.watch"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func extract(_ text: String) throws -> URL {
        if let url = try? normalize(text) { return url }
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, let safe = try? normalize(url.absoluteString) { return safe }
        }
        throw InputError.invalidURL
    }
}
