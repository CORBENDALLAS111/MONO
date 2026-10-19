import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    var model: AppModel?
    private var pendingCompletion: (() -> Void)?
    func attach(_ model: AppModel) {
        self.model = model
        if let pendingCompletion {
            model.backgroundCompletion = pendingCompletion
            self.pendingCompletion = nil
            model.finishBackgroundIfReady()
        }
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if let model { model.backgroundCompletion = completionHandler; model.finishBackgroundIfReady() }
        else { pendingCompletion = completionHandler }
    }
}

@main
struct MONOApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = Appearance.obsidian.rawValue
    var body: some Scene {
        WindowGroup {
            AppShell().environment(model)
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
                .tint(Color.primary)
                .task { delegate.attach(model); await model.recover() }
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
        .sheet(item: $model.manifest) { manifest in InspectorView(manifest: manifest) }
        .alert("error.title", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("ok") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
