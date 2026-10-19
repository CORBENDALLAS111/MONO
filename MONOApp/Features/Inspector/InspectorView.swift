import SwiftUI

struct InspectorView: View {
    let manifest: MediaManifest
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selections: [String: String] = [:]
    @State private var name = ""
    @State private var folder = "MONO"
    @State private var presetID: UUID?
    @State private var confirmLarge = false
    private var preset: DownloadPreset { model.presets.first { $0.id == presetID } ?? DownloadPreset(name: String(localized: "preset.best")) }
    private var total: Int64 { manifest.assets.flatMap(\.variants).filter { selections.values.contains($0.id) }.compactMap(\.bytes).reduce(0, +) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(manifest.sourceURL.host ?? "").font(.caption).foregroundStyle(.secondary)
                        Text(manifest.title).font(.title.weight(.semibold)).textSelection(.enabled)
                        if let creator = manifest.creator { Text(creator).foregroundStyle(.secondary) }
                        Text("inspector.metadata").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                }
                Section("inspector.assets") {
                    HStack {
                        Button("select.all") { selectDefaults() }
                        Spacer()
                        Button("select.none") { selections = [:] }
                    }
                    ForEach(Array(manifest.assets.enumerated()), id: \.element.id) { index, asset in
                        assetRow(asset, index: index)
                    }
                }
                Section("inspector.destination") {
                    TextField("filename", text: $name)
                    TextField("folder", text: $folder)
                    Picker("preset", selection: $presetID) {
                        ForEach(model.presets) { item in Text(item.name).tag(Optional(item.id)) }
                    }.onChange(of: presetID) { _, _ in selectDefaults() }
                    Text("destination.local").font(.footnote).foregroundStyle(.secondary)
                    if preset.saveToPhotos { Text("destination.photos").font(.footnote) }
                }
                Section {
                    Button {
                        if total >= 250 * 1024 * 1024 { confirmLarge = true }
                        else { download() }
                    } label: { ActionLabel(title: "download", icon: .download) }
                        .buttonStyle(.plain).disabled(selections.isEmpty || !model.storageReady)
                        .accessibilityIdentifier("downloadButton")
                    if total > 0 { Text(total.fileSize).foregroundStyle(.secondary) }
                    Text("rights").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("inspector.title").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { IconButton(token: .x, label: "close") { dismiss() } } }
            .confirmationDialog("large.confirm", isPresented: $confirmLarge) {
                Button("download") { download() }
            }
            .onAppear {
                name = manifest.title
                presetID = model.presets.first?.id
                selectDefaults()
            }
        }.tint(.primary)
    }
    @ViewBuilder private func assetRow(_ asset: MediaAsset, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { selections[asset.id] != nil }, set: { enabled in
                if enabled { selections[asset.id] = MediaVariant.best(asset.variants, smaller: preset.smaller)?.id }
                else { selections.removeValue(forKey: asset.id) }
            })) {
                HStack {
                    AppIcon(token: asset.kind == .video ? .video : .image)
                    Text("\(index + 1) · " + String(localized: asset.kind == .video ? "video" : "image"))
                }
            }.tint(.primary)
            if selections[asset.id] != nil {
                Picker("quality", selection: Binding(get: { selections[asset.id] ?? "" }, set: { selections[asset.id] = $0 })) {
                    ForEach(asset.variants) { variant in
                        Text(variant.quality + " · " + variant.mimeType + (variant.bytes.map { " · " + $0.fileSize } ?? "")).tag(variant.id)
                    }
                }
                if let variant = asset.variants.first(where: { $0.id == selections[asset.id] }) {
                    if asset.kind == .image { RemoteImagePreview(variant: variant) }
                    Text(details(variant)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 6)
    }
    private func details(_ variant: MediaVariant) -> String {
        [variant.codec, variant.fps.map { "\($0) FPS" }, variant.hasAudio.map { String(localized: $0 ? "audio.yes" : "audio.no") }].compactMap { $0 }.joined(separator: " · ")
    }
    private func selectDefaults() {
        selections = [:]
        for asset in manifest.assets where !preset.photosOnly || asset.kind == .image {
            selections[asset.id] = MediaVariant.best(asset.variants, smaller: preset.smaller)?.id
        }
    }
    private func download() {
        Task { await model.enqueue(manifest, variants: selections, name: name, folder: folder, preset: preset) }
    }
}
