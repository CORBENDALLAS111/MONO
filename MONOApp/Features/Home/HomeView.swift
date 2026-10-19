import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("haptics") private var haptics = true
    @FocusState private var inputFocused: Bool
    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "MONO")
                        .font(.caption.weight(.bold)).tracking(5)
                    Spacer()
                    Text("home.original").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 20)
                VStack(alignment: .leading, spacing: 18) {
                    Text("home.hero").font(.system(.largeTitle, design: .default, weight: .semibold))
                        .tracking(-1.3).fixedSize(horizontal: false, vertical: true)
                    Text("home.subtitle").foregroundStyle(.secondary).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 36).padding(.bottom, 18)
                VStack(alignment: .leading, spacing: 16) {
                    Text("home.link").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 10) {
                        AppIcon(token: .link).padding(.top, 12)
                        TextField("https://…", text: $model.input, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).lineLimit(1...5).focused($inputFocused)
                            .padding(.vertical, 12).accessibilityLabel("home.link").accessibilityIdentifier("urlInput")
                        if !model.input.isEmpty { IconButton(token: .x, label: "clear") { model.input = "" } }
                    }
                    GlassEffectContainer(spacing: 16) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { paste; analyze }
                            VStack(spacing: 12) { paste; analyze }
                        }
                    }
                }.modifier(Surface())
                Text("home.privacy").font(.footnote).foregroundStyle(.secondary).lineSpacing(3)
                if !model.library.isEmpty {
                    HStack {
                        Text("home.recent").font(.title3.weight(.semibold))
                        Spacer()
                        Button("all") { model.selectedTab = 2 }
                    }
                    ForEach(model.library.suffix(3).reversed()) { job in
                        HStack(spacing: 14) {
                            AppIcon(token: job.kind == .video ? .video : .image)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(job.name).font(.headline).lineLimit(2)
                                Text(job.received.fileSize).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            AppIcon(token: .check)
                        }.modifier(Surface())
                    }
                } else {
                    HStack(spacing: 12) {
                        AppIcon(token: .download)
                        Text("home.bytes").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                }
            }.padding(.horizontal, 24).padding(.bottom, 36)
        }
        .background { MonoBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.9), value: model.resolving)
    }
    private var paste: some View {
        PasteButton(payloadType: String.self) { values in
            if let value = values.first {
                model.input = value
                Task { await model.resolve() }
            }
        }.buttonStyle(.plain).labelStyle(.titleOnly)
            .frame(maxWidth: .infinity, minHeight: 48).modifier(GlassControl())
            .accessibilityLabel("paste").accessibilityIdentifier("pasteButton")
    }
    private var analyze: some View {
        Button {
            inputFocused = false
            if haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            Task { await model.resolve() }
        } label: {
            if model.resolving {
                ProgressView().tint(.primary).frame(maxWidth: .infinity, minHeight: 48).accessibilityLabel("analyzing")
            } else { ActionLabel(title: "continue", icon: .arrow_up_right) }
        }
        .buttonStyle(.plain).modifier(GlassControl())
        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.resolving)
        .accessibilityIdentifier("analyzeButton")
    }
}

#Preview { HomeView().environment(AppModel()).preferredColorScheme(.dark) }
