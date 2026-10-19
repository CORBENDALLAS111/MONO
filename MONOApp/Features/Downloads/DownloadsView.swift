import SwiftUI

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("downloads.subtitle").foregroundStyle(.secondary).padding(.vertical, 12)
                if model.jobs.isEmpty {
                    EmptyState(icon: .download, title: "downloads.empty", detail: "downloads.empty.detail")
                }
                ForEach(model.jobs.reversed()) { job in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            AppIcon(token: job.kind == .video ? .video : .image)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(job.name).font(.headline)
                                Text(job.sourceURL.host ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                        }
                        HStack {
                            Text(LocalizedStringKey("state." + job.state.rawValue)).font(.subheadline.weight(.medium))
                            Spacer()
                            if let progress = job.progress { Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
                        }
                        if job.state == .running {
                            if let progress = job.progress { ProgressView(value: progress).tint(.primary) }
                            else { ProgressView().tint(.primary) }
                            Text(job.received.fileSize + (job.total.map { " / " + $0.fileSize } ?? ""))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            if job.speed > 0 {
                                Text(Int64(job.speed).fileSize + "/s" + (job.eta.map { " · " + String(Int($0)) + " s" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        if let message = job.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        HStack(spacing: 18) {
                            if job.state == .running {
                                IconButton(token: .pause, label: "pause") { Task { await model.pause(job.id) } }
                            }
                            if job.state == .paused || job.state == .failed {
                                Button { Task { await model.retry(job.id) } } label: {
                                    HStack { AppIcon(token: .play); Text("retry") }.frame(minHeight: 44)
                                }.disabled(job.message == String(localized: "pause.preparing"))
                            }
                            Spacer()
                            if job.state.allows(.canceled) {
                                IconButton(token: .x, label: "cancel") { Task { await model.cancel(job.id) } }
                            }
                            if job.state == .completed { AppIcon(token: .check) }
                        }
                    }.modifier(Surface()).accessibilityElement(children: .contain)
                }
                Text("background.limit").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.background { MonoBackground() }
            .navigationTitle("tab.downloads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    IconButton(token: .list, label: "logs.title") { model.openLogs() }.accessibilityIdentifier("logsButton")
                }
            }
            .refreshable { await model.recover() }
    }
}
