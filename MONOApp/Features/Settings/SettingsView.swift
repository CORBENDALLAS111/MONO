import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = Appearance.obsidian.rawValue
    @AppStorage("haptics") private var haptics = true
    @AppStorage("wifiOnly") private var wifiOnly = false
    @AppStorage("lowData") private var lowData = false
    @AppStorage("concurrency") private var concurrency = 2
    @AppStorage("resolverEndpoint") private var storedEndpoint = ""
    @AppStorage("notifications") private var notifications = false
    @State private var token = ""
    @State private var endpoint = ""
    @State private var query = ""
    @State private var editingPreset: DownloadPreset?
    @State private var reset = false
    @State private var wipe = false
    @State private var advanced = false
    private func matches(_ key: String) -> Bool {
        let terms: [String: [String]] = [
            "settings.appearance": ["theme", "haptics", "settings.accessibility"],
            "settings.downloads": ["wifi.only", "low.data", "concurrency", "notifications"],
            "settings.advanced": ["resolver.endpoint", "resolver.token", "diagnostics.export"],
            "privacy": ["history.clear", "files.delete.all", "settings.reset"],
            "presets": ["preset.best", "preset.small", "preset.photos"]
        ]
        return query.isEmpty || ([key] + (terms[key] ?? [])).contains {
            String(localized: String.LocalizationValue($0)).localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        Form {
            if matches("settings.appearance") {
                Section("settings.appearance") {
                    Picker("theme", selection: $appearance) {
                        Text("theme.system").tag("system"); Text("Obsidian").tag("obsidian"); Text("Porcelain").tag("porcelain")
                    }
                    Toggle("haptics", isOn: $haptics)
                    Text("settings.accessibility").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if matches("settings.downloads") {
                Section("settings.downloads") {
                    Stepper(value: $concurrency, in: 1...4) { HStack { Text("concurrency"); Spacer(); Text("\(concurrency)") } }
                    Toggle("wifi.only", isOn: $wifiOnly)
                    Toggle("low.data", isOn: $lowData)
                    Text("settings.next").font(.footnote).foregroundStyle(.secondary)
                    Toggle("notifications", isOn: Binding(get: { notifications }, set: { enabled in
                        if !enabled { notifications = false; return }
                        Task {
                            do { notifications = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                            catch { model.error = String(localized: "error.permission") }
                        }
                    }))
                }
            }
            if matches("presets") {
                Section("presets") {
                    ForEach(model.presets) { preset in Button(preset.name) { editingPreset = preset } }
                    Button("preset.add") { editingPreset = DownloadPreset(name: String(localized: "preset.custom")) }
                }
            }
            if matches("settings.advanced") {
                Section {
                    DisclosureGroup("settings.advanced", isExpanded: $advanced) {
                        Text("resolver.explanation").font(.footnote).foregroundStyle(.secondary)
                        TextField("resolver.endpoint", text: $endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("resolver.token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("resolver.save") {
                            do {
                                if !endpoint.isEmpty { endpoint = try URLPolicy.normalize(endpoint).absoluteString }
                                if let url = URL(string: endpoint), url.query != nil { throw InputError.invalidURL }
                                try KeychainToken.write(token)
                                storedEndpoint = endpoint
                            } catch { model.error = String(localized: "error.settings") }
                        }
                        Text("direct/1.0 · resolver contract v1 · Swift 6 · iOS 26+").font(.caption).foregroundStyle(.secondary)
                        ShareLink(item: diagnostics) { Text("diagnostics.export") }
                    }
                }
            }
            if matches("privacy") {
                Section("privacy") {
                    Text("privacy.detail").font(.footnote).foregroundStyle(.secondary)
                    Button("history.clear") {
                        model.clearHistory()
                    }
                    Button("files.delete.all") { wipe = true }
                    Button("settings.reset") { reset = true }
                }
            }
            Section {
                Text("rights").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("licenses") { LicenseView() }
            }
        }.navigationTitle("tab.settings").searchable(text: $query, prompt: "search")
        .sheet(item: $editingPreset) { preset in PresetEditor(preset: preset) }
        .onAppear {
            endpoint = storedEndpoint
            do { token = try KeychainToken.read() }
            catch { model.error = String(localized: "error.settings") }
        }
        .confirmationDialog("settings.reset.confirm", isPresented: $reset) {
            Button("reset") {
                appearance = "obsidian"; haptics = true; wifiOnly = false; lowData = false; concurrency = 2; notifications = false
                model.snapshot.presets = DownloadPreset.defaults; _ = model.persist()
            }
        }
        .confirmationDialog("files.delete.confirm", isPresented: $wipe) {
            Button("delete") { for job in model.library { model.delete(job) } }
        }
    }
    private var diagnostics: String {
        // Deliberately omit URLs, titles, filenames, bearer tokens and server endpoint.
        "MONO diagnostics v1\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nJobs: \(model.jobs.count)\nCompleted: \(model.library.count)\nResolver: direct/1.0; contract v1\n"
    }
}

private struct LicenseView: View {
    @State private var text = ""
    var body: some View {
        ScrollView { Text(text).font(.footnote.monospaced()).textSelection(.enabled).padding(24) }
            .navigationTitle("licenses")
            .task {
                do {
                    guard let url = Bundle.main.url(forResource: "Lucide-LICENSE", withExtension: "txt") else { throw CocoaError(.fileNoSuchFile) }
                    text = try String(contentsOf: url, encoding: .utf8)
                } catch { text = String(localized: "error.file") }
            }
    }
}

struct PresetEditor: View {
    @State var preset: DownloadPreset
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("preset.name", text: $preset.name)
                Toggle("preset.smaller", isOn: $preset.smaller)
                Toggle("preset.photosOnly", isOn: $preset.photosOnly)
                Toggle("wifi.only", isOn: $preset.wifiOnly)
                Toggle("save.photos", isOn: $preset.saveToPhotos)
                Text("preset.honest").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("preset")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("save") { model.savePreset(preset); dismiss() }.disabled(preset.name.isEmpty) }
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
            }
        }
    }
}
