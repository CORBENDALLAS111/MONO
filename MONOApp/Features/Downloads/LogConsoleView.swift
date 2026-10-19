import SwiftUI

struct LogConsoleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var following = true
    private var effects: Bool { !reduceTransparency && !reduceMotion }
    var body: some View {
        let effectsEnabled = effects
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Circle().fill(.primary).frame(width: 5, height: 5)
                    Text("logs.live").font(.caption.weight(.semibold)).tracking(1.3)
                    Spacer()
                    Text("logs.events").font(.caption).foregroundStyle(.secondary)
                    Text(model.log.entries.count, format: .number).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 8)
                GeometryReader { viewport in
                    ScrollViewReader { scroll in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if model.log.entries.isEmpty {
                                    Text("logs.empty").font(.callout).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                                }
                                ForEach(model.log.entries) { entry in
                                    row(entry)
                                        .visualEffect { content, geometry in
                                            let top = geometry.frame(in: .named("logViewport")).minY
                                            let fade = effectsEnabled ? min(1, max(0, (84 - top) / 84)) : 0
                                            content.blur(radius: fade * 5).opacity(1 - Double(fade) * 0.65)
                                        }
                                        .id(entry.id)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .bottomLeading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 18)
                        }
                        .coordinateSpace(name: "logViewport")
                        .defaultScrollAnchor(.bottom)
                        .scrollIndicators(.hidden)
                        .mask {
                            if effectsEnabled {
                                VStack(spacing: 0) {
                                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: 76)
                                    Rectangle().fill(.white)
                                }
                            } else { Rectangle().fill(.white) }
                        }
                        .onScrollPhaseChange { _, phase in if phase == .interacting { following = false } }
                        .onChange(of: model.log.entries.last?.id) { _, id in
                            guard following, let id else { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scroll.scrollTo(id, anchor: .bottom) }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if !following {
                                Button {
                                    following = true
                                    if let id = model.log.entries.last?.id {
                                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { scroll.scrollTo(id, anchor: .bottom) }
                                    }
                                } label: { Text("logs.latest").font(.caption.weight(.medium)).padding(.horizontal, 16).frame(minHeight: 44) }
                                    .buttonStyle(.plain).modifier(GlassControl()).padding(18)
                            }
                        }
                    }
                }
                Text("logs.privacy").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
            }
            .background { MonoBackground() }
            .navigationTitle("logs.title").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ShareLink(item: model.log.exportText) { Text("logs.export") }
                        Button("logs.clear") { model.log.clear() }
                    } label: { AppIcon(token: .ellipsis).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("more")
                }
                ToolbarItem(placement: .confirmationAction) {
                    IconButton(token: .x, label: "close") { dismiss() }.accessibilityIdentifier("closeLogs")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(.primary)
    }
    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 13) {
            AppIcon(token: icon(entry.kind), size: 17).foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.kind.title).font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text(entry.date, format: .dateTime.hour().minute().second()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let detail = entry.detail { Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }
    private func icon(_ kind: LogKind) -> IconToken {
        switch kind {
        case .completed: .check
        case .failed, .storage: .circle_alert
        case .paused: .pause
        case .canceled: .x
        case .resolving, .resolved: .link
        case .started, .progress, .queued: .download
        default: .info
        }
    }
}
