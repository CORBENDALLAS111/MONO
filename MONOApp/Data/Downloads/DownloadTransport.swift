import Foundation

enum TransferEvent: Sendable {
    case progress(UUID, Int64, Int64)
    case staged(UUID, URL)
    case failed(UUID, String)
    case paused(UUID, Data?)
    case backgroundFinished
}

final class DownloadTransport: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    // Only URLSession's serial delegate queue mutates redirect counts.
    private var redirects: [Int: Int] = [:]
    private let redirectLock = NSLock()
    private func redirectCount(_ identifier: Int) -> Int {
        redirectLock.lock()
        defer { redirectLock.unlock() }
        let count = (redirects[identifier] ?? 0) + 1
        redirects[identifier] = count
        return count
    }
    private func clearRedirects(_ identifier: Int) {
        redirectLock.lock()
        defer { redirectLock.unlock() }
        redirects.removeValue(forKey: identifier)
    }
    private let emit: @Sendable (TransferEvent) -> Void
    private let staging: URL
    private let sessionIdentifier: String
    private var session: URLSession?
    init(staging: URL, emit: @escaping @Sendable (TransferEvent) -> Void) {
        self.staging = staging
        self.emit = emit
        sessionIdentifier = (Bundle.main.bundleIdentifier ?? "mono") + ".downloads.v1"
        super.init()
        let config: URLSessionConfiguration
        #if DEBUG
        if FixtureNetwork.active {
            config = .ephemeral
            config.protocolClasses = [FixtureNetwork.self]
        } else { config = .background(withIdentifier: sessionIdentifier); config.sessionSendsLaunchEvents = true }
        #else
        config = .background(withIdentifier: sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        #endif
        config.isDiscretionary = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }
    func tasks() async -> [URLSessionTask] {
        guard let session else { return [] }
        return await withCheckedContinuation { continuation in session.getAllTasks { continuation.resume(returning: $0) } }
    }
    func start(_ job: DownloadJob, resumeData: Data?, cellular: Bool, lowData: Bool) {
        guard let session else { emit(.failed(job.id, String(localized: "error.transfer"))); return }
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: job.variant.url)
            request.allowsCellularAccess = cellular && !job.preset.wifiOnly
            request.allowsConstrainedNetworkAccess = !lowData
            request.allowsExpensiveNetworkAccess = cellular && !job.preset.wifiOnly
            task = session.downloadTask(with: request)
        }
        task.taskDescription = job.id.uuidString
        task.resume()
    }
    func pause(_ id: UUID) async -> Bool {
        for task in await tasks() where task.taskDescription == id.uuidString {
            if let download = task as? URLSessionDownloadTask {
                download.cancel { [emit] data in emit(.paused(id, data)) }
                return true
            }
        }
        return false
    }
    func cancel(_ id: UUID) async {
        for task in await tasks() where task.taskDescription == id.uuidString { task.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        if totalBytesWritten > FileVerifier.maximumBytes || totalBytesExpectedToWrite > FileVerifier.maximumBytes {
            downloadTask.cancel()
            emit(.failed(id, InputError.limit.localizedDescription))
        } else { emit(.progress(id, totalBytesWritten, totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else { throw InputError.http((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0) }
            guard FileVerifier.extensions[response.mimeType ?? ""] != nil else { throw InputError.invalidFile }
            let destination = staging.appendingPathComponent(id.uuidString + ".staged")
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            emit(.staged(id, destination))
        } catch { emit(.failed(id, error.localizedDescription)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        clearRedirects(task.taskIdentifier)
        guard let error, let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        // Never expose URLSession's error userInfo (it may contain signed URLs).
        if (error as NSError).code != NSURLErrorCancelled {
            emit(.failed(id, String(localized: "error.transfer") + " (\((error as NSError).code))"))
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        let count = redirectCount(task.taskIdentifier)
        guard count <= 5, let url = request.url else { return nil }
        do {
            try await URLPolicy.validate(url)
            var safe = request
            safe.setValue(nil, forHTTPHeaderField: "Authorization")
            safe.setValue(nil, forHTTPHeaderField: "Cookie")
            return safe
        } catch { return nil }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { emit(.backgroundFinished) }
}
