import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class AppModel {
    var snapshot = LibrarySnapshot()
    var manifest: MediaManifest?
    var sheet: AppSheet?
    var log = ActivityLog()
    var input = ""
    var resolving = false
    var error: String?
    var selectedTab = 0
    var storageReady = false
    private var disk: DiskStore?
    @ObservationIgnored private var transport: DownloadTransport?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var samples: [UUID: (Date, Int64)] = [:]
    @ObservationIgnored private var scheduling = false
    @ObservationIgnored private var completionsInFlight = 0
    @ObservationIgnored private var processingIDs: Set<UUID> = []
    @ObservationIgnored private var backgroundFinished = false
    @ObservationIgnored var backgroundCompletion: (() -> Void)?
    var jobs: [DownloadJob] { snapshot.jobs }
    var library: [DownloadJob] { jobs.filter { $0.state == .completed && $0.file != nil } }
    var presets: [DownloadPreset] { snapshot.presets }

    init() {
        do {
            let disk: DiskStore
            #if DEBUG
            if FixtureNetwork.isolatedStorage { disk = try DiskStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
            else { disk = try DiskStore() }
            #else
            disk = try DiskStore()
            #endif
            self.disk = disk
            snapshot = try disk.load()
            input = snapshot.pendingInput ?? ""
            storageReady = true
            let (events, continuation) = AsyncStream<TransferEvent>.makeStream()
            transport = DownloadTransport(staging: disk.root) { event in
                continuation.yield(event)
            }
            eventTask = Task { [weak self] in
                for await event in events { await self?.handle(event) }
            }
            log.append(.ready)
        } catch {
            self.error = String(localized: "error.storage")
        }
    }
    func persist() -> Bool {
        guard storageReady, let disk else { return false }
        snapshot.pendingInput = input.isEmpty ? nil : input
        do { try disk.save(snapshot); return true }
        catch { self.error = String(localized: "error.storage"); log.append(.storage); return false }
    }
    func resolve() async {
        guard !resolving else { return }
        resolving = true
        log.append(.resolving)
        defer { resolving = false }
        do {
            let url = try URLPolicy.extract(input)
            let endpoint = UserDefaults.standard.string(forKey: "resolverEndpoint") ?? ""
            let token: String
            if URLPolicy.isSocial(url) {
                guard !endpoint.isEmpty else { throw InputError.backendMissing }
                token = try KeychainToken.read()
            } else { token = "" }
            manifest = try await ResolverRegistry(endpoint: endpoint, token: token).resolve(url)
            log.append(.resolved, detail: String(manifest?.assets.count ?? 0))
            if case nil = sheet, let manifest { sheet = .inspector(manifest) }
        } catch is CancellationError { return }
        catch {
            self.error = error is InputError ? error.localizedDescription : String(localized: "error.network")
            log.append(.failed, detail: self.error)
        }
    }
    func ingest(_ url: URL) {
        do {
            if url.scheme == "mono" {
                guard url.host == "import", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let raw = components.queryItems?.first(where: { $0.name == "url" })?.value else { throw InputError.invalidURL }
                input = try URLPolicy.normalize(raw).absoluteString
            } else { input = try URLPolicy.normalize(url.absoluteString).absoluteString }
            selectedTab = 0
        } catch { self.error = error.localizedDescription }
    }
    func drainInbox() {
        #if DEBUG
        if FixtureNetwork.isolatedStorage { return }
        #endif
        do {
            for (path, request) in try ShareInbox.read() {
                let receipt = request.id + ":" + String(request.created.timeIntervalSince1970)
                if snapshot.consumedInbox.contains(receipt) { try FileManager.default.removeItem(at: path); continue }
                // Leave subsequent items pending until the user handles this URL.
                guard input.isEmpty else { return }
                let url = try URLPolicy.normalize(request.url.absoluteString)
                input = url.absoluteString
                snapshot.consumedInbox.insert(receipt)
                guard persist() else { return }
                try FileManager.default.removeItem(at: path)
                selectedTab = 0
                return
            }
        } catch {
            // A missing App Group must not silently pretend sharing worked.
            self.error = String(localized: "error.inbox")
        }
    }
    func recover() async {
        guard !scheduling else { return }
        guard let transport, let disk else { return }
        let tasks = await transport.tasks()
        let ids = Set(tasks.compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
        for task in tasks where !snapshot.jobs.contains(where: { $0.id.uuidString == task.taskDescription }) { task.cancel() }
        for job in snapshot.jobs {
            guard let i = index(job.id) else { continue }
            if ids.contains(job.id), job.state == .running { continue }
            let staged = disk.file(job.id.uuidString + ".staged")
            let final = disk.file(job.id.uuidString + "." + (FileVerifier.extensions[job.variant.mimeType] ?? "bin"))
            if (FileManager.default.fileExists(atPath: staged.path) || FileManager.default.fileExists(atPath: final.path)), job.state == .running || job.state == .processing {
                await handle(.staged(job.id, FileManager.default.fileExists(atPath: staged.path) ? staged : final))
            } else if job.state == .running || job.state == .processing {
                snapshot.jobs[i].state = .failed
                snapshot.jobs[i].message = String(localized: "interrupted")
            } else if job.state == .completed, let file = job.file, !FileManager.default.fileExists(atPath: disk.file(file).path) {
                snapshot.jobs[i].state = .failed
                snapshot.jobs[i].message = String(localized: "error.file")
            }
        }
        _ = persist()
        log.append(.recovered, detail: String(tasks.count))
        await schedule()
    }
    func enqueue(_ manifest: MediaManifest, variants: [String: String], name: String, folder: String, preset: DownloadPreset) async {
        guard storageReady else { return }
        for asset in manifest.assets {
            guard !preset.photosOnly || asset.kind == .image,
                  let id = variants[asset.id], let variant = asset.variants.first(where: { $0.id == id }) else { continue }
            if snapshot.jobs.contains(where: { $0.variant.url == variant.url && $0.state != .canceled && $0.state != .failed }) { continue }
            snapshot.jobs.append(DownloadJob(sourceURL: manifest.sourceURL, variant: variant, kind: asset.kind,
                                             name: FileNames.safe(name), folder: FileNames.safe(folder), preset: preset))
            log.append(.queued)
        }
        guard persist() else { return }
        self.manifest = nil
        sheet = nil
        input = ""
        _ = persist()
        selectedTab = 1
        await schedule()
    }
    func schedule() async {
        guard !scheduling, let transport, let disk, storageReady else { return }
        scheduling = true
        defer { scheduling = false }
        let defaults = UserDefaults.standard
        let limit = max(1, min(4, defaults.integer(forKey: "concurrency") == 0 ? 2 : defaults.integer(forKey: "concurrency")))
        while snapshot.jobs.filter({ $0.state == .running }).count < limit,
              let i = snapshot.jobs.firstIndex(where: { $0.state == .waiting }) {
            let id = snapshot.jobs[i].id
            // Reserve before suspension; cancellation can still win while DNS is checked.
            snapshot.jobs[i].state = .running
            guard persist() else { snapshot.jobs[i].state = .waiting; return }
            do {
                let url = snapshot.jobs[i].variant.url
                try await URLPolicy.validate(url)
                guard let current = index(id), snapshot.jobs[current].state == .running else { continue }
                let path = disk.resumeFile(id)
                let resumeData = FileManager.default.fileExists(atPath: path.path) ? try Data(contentsOf: path) : nil
                transport.start(snapshot.jobs[current], resumeData: resumeData,
                                cellular: !defaults.bool(forKey: "wifiOnly"), lowData: defaults.bool(forKey: "lowData"))
                log.append(.started)
                samples[id] = (Date(), snapshot.jobs[current].received)
            } catch {
                if let current = index(id), snapshot.jobs[current].state == .running {
                    snapshot.jobs[current].state = .failed
                    snapshot.jobs[current].message = error is InputError ? error.localizedDescription : String(localized: "error.transfer")
                }
            }
        }
        _ = persist()
    }
    func pause(_ id: UUID) async {
        guard let i = index(id), jobs[i].state == .running else { return }
        snapshot.jobs[i].state = .paused
        log.append(.paused)
        snapshot.jobs[i].message = String(localized: "pause.preparing")
        _ = persist()
        let requested = await transport?.pause(id) ?? false
        if !requested { await handle(.paused(id, nil)) }
        await schedule()
    }
    func retry(_ id: UUID) async {
        guard let i = index(id), jobs[i].state == .failed || jobs[i].state == .paused,
              jobs[i].message != String(localized: "pause.preparing") else { return }
        snapshot.jobs[i].state = .waiting
        snapshot.jobs[i].message = nil
        guard persist() else { return }
        await schedule()
    }
    func cancel(_ id: UUID) async {
        guard let i = index(id), jobs[i].state.allows(.canceled) else { return }
        snapshot.jobs[i].state = .canceled
        log.append(.canceled)
        _ = persist()
        await transport?.cancel(id)
        await schedule()
    }
    private func index(_ id: UUID) -> Int? { snapshot.jobs.firstIndex { $0.id == id } }
    private func handle(_ event: TransferEvent) async {
        guard let disk else { return }
        switch event {
        case .progress(let id, let received, let total):
            guard let i = index(id), jobs[i].state == .running else { return }
            let now = Date(), previous = samples[id] ?? (now, received)
            let elapsed = now.timeIntervalSince(previous.0)
            snapshot.jobs[i].received = received
            snapshot.jobs[i].total = total > 0 ? total : nil
            if elapsed >= 0.5 {
                snapshot.jobs[i].speed = max(0, Double(received - previous.1) / elapsed)
                samples[id] = (now, received)
                log.append(.progress, detail: received.fileSize + (total > 0 ? " / " + total.fileSize : ""))
            }
        case .paused(let id, let data):
            guard let i = index(id), jobs[i].state == .paused else { return }
            do {
                if let data { try data.write(to: disk.resumeFile(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                else if FileManager.default.fileExists(atPath: disk.resumeFile(id).path) { try FileManager.default.removeItem(at: disk.resumeFile(id)) }
                snapshot.jobs[i].message = String(localized: data == nil ? "pause.restart" : "pause.resume")
            } catch { self.error = String(localized: "error.storage"); snapshot.jobs[i].message = String(localized: "pause.restart") }
            _ = persist()
        case .failed(let id, let message):
            guard let i = index(id), jobs[i].state == .running else { return }
            snapshot.jobs[i].state = .failed
            snapshot.jobs[i].message = message
            log.append(.failed, detail: message)
            // A rejected/expired resume blob must not create an endless retry loop.
            if FileManager.default.fileExists(atPath: disk.resumeFile(id).path) {
                do { try FileManager.default.removeItem(at: disk.resumeFile(id)) }
                catch { self.error = String(localized: "error.storage") }
            }
            _ = persist()
            await schedule()
        case .staged(let id, let staged):
            guard !processingIDs.contains(id) else { return }
            guard let i = index(id), jobs[i].state == .running || jobs[i].state == .processing else {
                try? FileManager.default.removeItem(at: staged)
                return
            }
            snapshot.jobs[i].state = .processing
            processingIDs.insert(id)
            _ = persist()
            completionsInFlight += 1
            defer { processingIDs.remove(id); completionsInFlight -= 1; finishBackgroundIfReady() }
            do {
                let mime = jobs[i].variant.mimeType
                let kind = jobs[i].kind
                let (digest, size) = try await Task.detached(priority: .utility) { try FileVerifier.verify(staged, mime: mime) }.value
                let metadata = try await LocalMediaInspector.inspect(staged, kind: kind)
                guard let i = index(id) else { return }
                let ext = FileVerifier.extensions[mime] ?? "bin"
                let filename = id.uuidString + "." + ext
                if let duplicate = library.first(where: { $0.digest == digest }), let existing = duplicate.file {
                    try FileManager.default.removeItem(at: staged)
                    snapshot.jobs[i].file = existing
                } else {
                    if staged != disk.file(filename) { try FileManager.default.moveItem(at: staged, to: disk.file(filename)) }
                    snapshot.jobs[i].file = filename
                }
                snapshot.jobs[i].digest = digest
                snapshot.jobs[i].metadata = metadata
                snapshot.jobs[i].received = size
                snapshot.jobs[i].total = size
                snapshot.jobs[i].state = .completed
                log.append(.completed, detail: size.fileSize)
                snapshot.jobs[i].message = nil
                guard persist() else { return }
                let resume = disk.resumeFile(id)
                if FileManager.default.fileExists(atPath: resume.path) {
                    do { try FileManager.default.removeItem(at: resume) }
                    catch { self.error = String(localized: "error.storage") }
                }
                if jobs[i].preset.saveToPhotos, let file = jobs[i].file {
                    do { try await PhotosExporter.save(disk.file(file), kind: jobs[i].kind) }
                    catch {
                        if let current = index(id) { snapshot.jobs[current].message = String(localized: "error.photos"); _ = persist() }
                    }
                }
                if UserDefaults.standard.bool(forKey: "notifications") {
                    let content = UNMutableNotificationContent()
                    content.title = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "MONO"
                    content.body = String(localized: "download.complete")
                    do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil)) }
                    catch { self.error = String(localized: "error.permission") }
                }
            } catch {
                if FileManager.default.fileExists(atPath: staged.path) {
                    do { try FileManager.default.removeItem(at: staged) }
                    catch { self.error = String(localized: "error.storage") }
                }
                if let current = index(id) {
                    snapshot.jobs[current].state = .failed
                    snapshot.jobs[current].message = error is InputError ? error.localizedDescription : String(localized: "error.storage")
                }
                log.append(.failed, detail: error is InputError ? error.localizedDescription : String(localized: "error.storage"))
                _ = persist()
            }
            await schedule()
        case .backgroundFinished:
            backgroundFinished = true
            finishBackgroundIfReady()
        }
    }
    func finishBackgroundIfReady() {
        if backgroundFinished && completionsInFlight == 0, let completion = backgroundCompletion {
            backgroundCompletion = nil
            backgroundFinished = false
            completion()
        }
    }
    func fileURL(_ job: DownloadJob) -> URL? { job.file.flatMap { disk?.file($0) } }
    func update(_ job: DownloadJob) {
        guard let i = index(job.id) else { return }
        snapshot.jobs[i] = job
        _ = persist()
    }
    func delete(_ job: DownloadJob) {
        do {
            if let file = job.file, !jobs.contains(where: { $0.id != job.id && $0.file == file }), let disk {
                if FileManager.default.fileExists(atPath: disk.file(file).path) { try FileManager.default.removeItem(at: disk.file(file)) }
            }
            if let disk {
                for path in [disk.resumeFile(job.id), disk.file(job.id.uuidString + ".staged")] where FileManager.default.fileExists(atPath: path.path) {
                    try FileManager.default.removeItem(at: path)
                }
            }
            snapshot.jobs.removeAll { $0.id == job.id }
            _ = persist()
        } catch { self.error = String(localized: "error.storage") }
    }
    func savePreset(_ preset: DownloadPreset) {
        if let i = snapshot.presets.firstIndex(where: { $0.id == preset.id }) { snapshot.presets[i] = preset }
        else { snapshot.presets.append(preset) }
        _ = persist()
    }
    func clearHistory() {
        for job in snapshot.jobs where job.state == .failed || job.state == .canceled { delete(job) }
    }
    func openLogs() { sheet = .logs }
    func dismissSheet() {
        if case .inspector = sheet { manifest = nil }
        sheet = nil
    }
    func showPendingInspector() {
        if case nil = sheet, let manifest { sheet = .inspector(manifest) }
    }
}
