import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    // Initialize background-session ownership before UIKit delivers background events,
    // even when no foreground SwiftUI task has run yet.
    let model = AppModel()
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        model.backgroundCompletion = completionHandler
        model.finishBackgroundIfReady()
    }
}

@main
struct MONOApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("appearance") private var appearance = Appearance.obsidian.rawValue
    var body: some Scene {
        WindowGroup {
            AppShell().environment(delegate.model)
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
                .tint(Color.primary)
                .task { await delegate.model.recover() }
        }
    }
}

struct AppShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label { Text("tab.home") } icon: { IconToken.house.tabImage } }.tag(0)
            NavigationStack { DownloadsView() }
                .tabItem { Label { Text("tab.downloads") } icon: { IconToken.list.tabImage } }.tag(1)
            NavigationStack { LibraryView() }
                .tabItem { Label { Text("tab.library") } icon: { IconToken.folder_open.tabImage } }.tag(2)
            NavigationStack { SettingsView() }
                .tabItem { Label { Text("tab.settings") } icon: { IconToken.settings_2.tabImage } }.tag(3)
        }
        .onOpenURL { model.ingest($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.drainInbox() }
            if phase == .background { _ = model.persist() }
        }
        .sheet(item: Binding(get: { model.sheet }, set: { if $0 == nil { model.dismissSheet() } }), onDismiss: { model.showPendingInspector() }) { sheet in
            switch sheet {
            case .inspector(let manifest): InspectorView(manifest: manifest)
            case .logs: LogConsoleView()
            }
        }
        .alert("error.title", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("ok") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
