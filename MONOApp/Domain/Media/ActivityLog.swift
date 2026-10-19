import Foundation

enum LogKind: String, Sendable, Equatable {
    case ready, resolving, resolved, queued, started, progress, paused, canceled, completed, failed, recovered, storage
    var title: String { String(localized: String.LocalizationValue("log." + rawValue)) }
}
struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let date = Date()
    let kind: LogKind
    let detail: String?
}
struct ActivityLog: Sendable {
    private(set) var entries: [LogEntry] = []
    let capacity: Int
    init(capacity: Int = 250) { self.capacity = max(1, min(500, capacity)) }
    mutating func append(_ kind: LogKind, detail: String? = nil) {
        entries.append(LogEntry(kind: kind, detail: detail.map(Self.redact)))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }
    mutating func clear() { entries.removeAll(keepingCapacity: true) }
    var exportText: String {
        (["MONO · activity log · " + Date().ISO8601Format()] + entries.map {
            $0.date.ISO8601Format() + " · " + $0.kind.title + ($0.detail.map { " · " + $0 } ?? "")
        }).joined(separator: "\n")
    }
    static func redact(_ input: String) -> String {
        let patterns = [
            "(?i)(?:https?|file)://\\S+",
            "(?i)(?:authorization|cookie|set-cookie)\\s*:[^\\r\\n]*",
            "(?i)\\bbearer\\s+\\S+",
            "(?i)(?:token|api[_-]?key|password)[\\\"']?\\s*[=:]\\s*[\\\"']?[^\\s,}]+"
        ]
        return patterns.reduce(String(input.prefix(1000))) {
            $0.replacingOccurrences(of: $1, with: "[redacted]", options: .regularExpression)
        }
    }
}

enum AppSheet: Identifiable {
    case inspector(MediaManifest), logs
    var id: String {
        switch self { case .inspector(let manifest): "inspector-" + manifest.id; case .logs: "logs" }
    }
}
