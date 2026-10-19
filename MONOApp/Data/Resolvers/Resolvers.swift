import Foundation

protocol MediaResolver: Sendable {
    func canHandle(_ url: URL) -> Bool
    func resolve(_ url: URL) async throws -> MediaManifest
}

/// No redirects for authenticated requests: never forwards a bearer to another origin.
final class SafeSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let allowRedirects: Bool
    init(allowRedirects: Bool) { self.allowRedirects = allowRedirects }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard allowRedirects, task.countOfBytesReceived < 65536,
              let url = request.url, (task.taskDescription.flatMap(Int.init) ?? 0) < 5 else { return nil }
        do {
            try await URLPolicy.validate(url)
            task.taskDescription = String((task.taskDescription.flatMap(Int.init) ?? 0) + 1)
            var safe = request
            safe.setValue(nil, forHTTPHeaderField: "Authorization")
            safe.setValue(nil, forHTTPHeaderField: "Cookie")
            return safe
        } catch { return nil }
    }
}

struct SafeHTTP: Sendable {
    let session: URLSession
    init(redirects: Bool = true) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.httpCookieStorage = nil
        config.urlCache = nil
        #if DEBUG
        if FixtureNetwork.active { config.protocolClasses = [FixtureNetwork.self] }
        #endif
        session = URLSession(configuration: config, delegate: SafeSessionDelegate(allowRedirects: redirects), delegateQueue: nil)
    }
    func bounded(_ request: URLRequest, limit: Int = 512 * 1024) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw InputError.invalidURL }
        try await URLPolicy.validate(url)
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw InputError.invalidManifest }
        guard (200...299).contains(response.statusCode) else { throw InputError.http(response.statusCode) }
        var data = Data()
        for try await byte in stream {
            guard data.count < limit else { throw InputError.limit }
            data.append(byte)
        }
        return (data, response)
    }
}

struct GenericDirectMediaResolver: MediaResolver {
    let http: SafeHTTP
    init(http: SafeHTTP = SafeHTTP()) { self.http = http }
    func canHandle(_ url: URL) -> Bool { !URLPolicy.isSocial(url) }
    func resolve(_ url: URL) async throws -> MediaManifest {
        try await URLPolicy.validate(url)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, raw) = try await http.session.data(for: request)
        guard let response = raw as? HTTPURLResponse else { throw InputError.invalidManifest }
        guard (200...299).contains(response.statusCode) else { throw InputError.http(response.statusCode) }
        let mime = (response.mimeType ?? "").lowercased()
        guard FileVerifier.extensions[mime] != nil else { throw InputError.unsupported }
        guard let finalURL = response.url else { throw InputError.invalidURL }
        try await URLPolicy.validate(finalURL)
        let length = response.expectedContentLength
        guard length <= FileVerifier.maximumBytes else { throw InputError.limit }
        let variant = MediaVariant(id: FileNames.identity(finalURL), url: finalURL, mimeType: mime, bytes: length > 0 ? length : nil)
        let kind: MediaKind = mime.hasPrefix("video/") ? .video : .image
        return MediaManifest(id: FileNames.identity(url), sourceURL: url,
                             title: FileNames.safe(url.deletingPathExtension().lastPathComponent),
                             resolver: "direct/1.0", assets: [MediaAsset(id: variant.id, kind: kind, variants: [variant])])
    }
}

struct AuthorizedServiceResolver: MediaResolver {
    let endpoint: URL
    let token: String
    let http = SafeHTTP(redirects: false)
    func canHandle(_ url: URL) -> Bool { URLPolicy.isSocial(url) }
    func resolve(_ url: URL) async throws -> MediaManifest {
        try await URLPolicy.validate(url)
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/resolve"))
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": url.absoluteString])
        let (data, _) = try await http.bounded(request)
        let manifest = try JSONDecoder().decode(MediaManifest.self, from: data)
        guard manifest.sourceURL == url, !manifest.assets.isEmpty, manifest.assets.count <= 50,
              Set(manifest.assets.map(\.id)).count == manifest.assets.count,
              manifest.title.count <= 500, manifest.id.count <= 256 else { throw InputError.invalidManifest }
        for asset in manifest.assets {
            guard !asset.variants.isEmpty, asset.variants.count <= 20,
                  Set(asset.variants.map(\.id)).count == asset.variants.count else { throw InputError.invalidManifest }
            for variant in asset.variants {
                guard FileVerifier.extensions[variant.mimeType] != nil,
                      variant.mimeType.hasPrefix(asset.kind == .video ? "video/" : "image/"),
                      (variant.bytes ?? 0) >= 0, (variant.bytes ?? 0) <= FileVerifier.maximumBytes,
                      (variant.width ?? 0) >= 0, (variant.width ?? 0) <= 16384,
                      (variant.height ?? 0) >= 0, (variant.height ?? 0) <= 16384 else { throw InputError.invalidManifest }
                try await URLPolicy.validate(variant.url)
            }
        }
        return manifest
    }
}

struct ResolverRegistry: Sendable {
    let endpoint: String
    let token: String
    func resolve(_ url: URL) async throws -> MediaManifest {
        if URLPolicy.isSocial(url) {
            guard !endpoint.isEmpty, !token.isEmpty else { throw InputError.backendMissing }
            let server = try URLPolicy.normalize(endpoint)
            guard server.query == nil else { throw InputError.invalidURL }
            return try await AuthorizedServiceResolver(endpoint: server, token: token).resolve(url)
        }
        return try await GenericDirectMediaResolver().resolve(url)
    }
}
