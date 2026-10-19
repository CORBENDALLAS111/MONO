import SwiftUI
import UIKit

enum Appearance: String, CaseIterable {
    case system, obsidian, porcelain
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .obsidian: .dark; case .porcelain: .light }
    }
}

struct AppIcon: View {
    let token: IconToken
    var size: CGFloat = 22
    var body: some View {
        LucideShape(token: token).stroke(style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

extension IconToken {
    /// UITabBar accepts Image content; rasterize the same native vector at display scale.
    @MainActor var tabImage: Image {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let path = LucideShape(token: self).path(in: CGRect(origin: .zero, size: size))
            context.cgContext.addPath(path.cgPath)
            context.cgContext.setStrokeColor(UIColor.label.cgColor)
            context.cgContext.setLineWidth(2)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            context.cgContext.strokePath()
        }
        return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
    }
}

struct IconButton: View {
    let token: IconToken
    let label: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) { AppIcon(token: token).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
            .accessibilityLabel(label)
    }
}

struct MonoBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack(alignment: .top) {
            (scheme == .dark ? Color.black : Color.white)
            if !reduceTransparency {
                RadialGradient(colors: [Color(white: scheme == .dark ? 0.22 : 0.9), .clear], center: .init(x: 0.78, y: 0.05), startRadius: 5, endRadius: 390)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct Surface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(20)
            .background(Color(white: scheme == .dark ? 0.085 : 0.96), in: RoundedRectangle(cornerRadius: 26))
    }
}

struct GlassControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: scheme == .dark ? 0.16 : 0.92), in: Capsule())
        } else { content.glassEffect(.regular.interactive(), in: .capsule) }
    }
}

struct ActionLabel: View {
    let title: LocalizedStringKey
    let icon: IconToken
    var body: some View {
        HStack(spacing: 10) { AppIcon(token: icon); Text(title) }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
    }
}

struct EmptyState: View {
    let icon: IconToken
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppIcon(token: icon, size: 32).padding(.bottom, 12)
            Text(title).font(.title2.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 32).modifier(Surface())
    }
}

extension Int64 {
    var fileSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
