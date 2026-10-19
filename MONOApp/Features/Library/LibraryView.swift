import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import UIKit

struct FilesExportRequest: Identifiable { let id = UUID(); let url: URL }
struct FilesExportPicker: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("libraryGrid") private var grid = true
    @State private var query = ""
    @State private var kind = "all"
    @State private var source = "all"
    @State private var folder = "all"
    @State private var favorites = false
    @State private var newest = true
    @State private var preview: URL?
    @State private var deleting: DownloadJob?
    @State private var editing: DownloadJob?
    @State private var exporting: FilesExportRequest?
    private var filtered: [DownloadJob] {
        model.library.filter { job in
            (kind == "all" || job.kind.rawValue == kind) && (!favorites || job.favorite) &&
            (source == "all" || job.sourceURL.host == source) && (folder == "all" || job.folder == folder) &&
            (query.isEmpty || [job.name, job.folder, job.sourceURL.host ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }.sorted { newest ? $0.created > $1.created : $0.created < $1.created }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(storageBytes.fileSize + " · " + String(model.library.count))
                    .font(.subheadline).foregroundStyle(.secondary)
                if filtered.isEmpty {
                    EmptyState(icon: .folder_open, title: "library.empty", detail: "library.empty.detail")
                }
                LazyVGrid(columns: grid ? [GridItem(.adaptive(minimum: 145), spacing: 16)] : [GridItem(.flexible())], spacing: 18) {
                    ForEach(filtered) { job in cell(job) }
                }
            }.padding(24)
        }
        .background { MonoBackground() }.navigationTitle("tab.library")
        .searchable(text: $query, prompt: "search")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("type", selection: $kind) {
                        Text("all").tag("all"); Text("video").tag("video"); Text("image").tag("image")
                    }
                    Picker("source", selection: $source) {
                        Text("all").tag("all")
                        ForEach(Array(Set(model.library.compactMap { $0.sourceURL.host })).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("folder", selection: $folder) {
                        Text("all").tag("all")
                        ForEach(Array(Set(model.library.map(\.folder))).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("favorites", isOn: $favorites)
                    Toggle("newest", isOn: $newest)
                    Toggle("grid", isOn: $grid)
                } label: { AppIcon(token: .sliders_horizontal).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("filters")
            }
        }
        .quickLookPreview($preview)
        .sheet(item: $editing) { job in RenameView(job: job) }
        .confirmationDialog("delete.confirm", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("delete") { if let deleting { model.delete(deleting) }; deleting = nil }
        }
        .sheet(item: $exporting) { request in FilesExportPicker(url: request.url) }
    }
    private var storageBytes: Int64 {
        var counted = Set<String>()
        return model.library.reduce(Int64(0)) { total, job in
            guard let file = job.file, counted.insert(file).inserted else { return total }
            return total + job.received
        }
    }
    private func cell(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                preview = model.fileURL(job)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    LocalThumbnail(url: model.fileURL(job), kind: job.kind)
                    Text(job.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(job.created, style: .date).font(.caption).foregroundStyle(.secondary)
                    if let metadata = job.metadata, let width = metadata.width, let height = metadata.height {
                        Text("\(width) × \(height)" + (metadata.codec.map { " · " + $0 } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text(job.name)).accessibilityHint("preview")
            HStack {
                Text(job.received.fileSize).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    if let url = model.fileURL(job) {
                        ShareLink(item: url) { Label { Text("share") } icon: { AppIcon(token: .share_2) } }
                        Button("save.files") { exporting = FilesExportRequest(url: url) }
                        Button("save.photos") {
                            Task {
                                do { try await PhotosExporter.save(url, kind: job.kind) }
                                catch { model.error = String(localized: "error.photos") }
                            }
                        }
                    }
                    Button(LocalizedStringKey(job.favorite ? "unfavorite" : "favorite")) { var updated = job; updated.favorite.toggle(); model.update(updated) }
                    Button("rename") { editing = job }
                    Button("delete") { deleting = job }
                } label: { AppIcon(token: .ellipsis).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("more")
            }
        }.modifier(Surface())
    }
}

struct RenameView: View {
    @State var job: DownloadJob
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form { TextField("filename", text: $job.name); TextField("folder", text: $job.folder) }
                .navigationTitle("rename")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("save") {
                        job.name = FileNames.safe(job.name); job.folder = FileNames.safe(job.folder)
                        model.update(job); dismiss()
                    } }
                    ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
                }
        }
    }
}
