import SwiftUI

@main
struct OrchardApp: App {
    @StateObject private var services = AppServices.forLaunch()
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var updater = UpdaterService()

    init() {
        // Apply the persisted Dock-icon preference before any window appears. Read
        // straight from defaults: the services aren't built yet. Only the hidden case
        // needs applying - the app launches as .regular anyway, and applying .regular
        // here would trigger the restore-activation dance at every launch.
        if UserDefaults.standard.bool(forKey: SettingsStore.hideDockIconDefaultsKey) {
            DockIconPolicy.apply(hidden: true)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .injectServices(services)
                .environmentObject(updater)
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Command Palette...") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ToggleCommandPalette"), object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                CheckForUpdatesView(updater: updater)

                Divider()

                Button("Orchard Help") {
                    if let url = URL(string: "https://github.com/andrew-waters/orchard") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            CommandMenu("Builds") {
                BuildsMenuCommands(buildService: services.imageBuildService)
            }
        }



        WindowGroup(id: "logs", for: LogTarget.self) { $target in
            MultiLogView(initialTarget: target)
                .injectServices(services)
        }
        .defaultSize(width: 900, height: 600)
        .windowToolbarStyle(.unified(showsTitle: false))

        WindowGroup(id: "build-log", for: UUID.self) { $buildID in
            BuildLogWindow(buildID: buildID)
                .injectServices(services)
        }
        .defaultSize(width: 680, height: 460)

        MenuBarExtra {
            MenuBarView()
                .injectServices(services)
        } label: {
            SwiftUI.Image("MenuBarLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .injectServices(services)
                .environmentObject(updater)
        }
    }
}

/// Injects every per-domain service as an environment object at a scene root.
extension View {
    func injectServices(_ s: AppServices) -> some View {
        environmentObject(s.alertCenter)
            .environmentObject(s.settings)
            .environmentObject(s.terminalLauncher)
            .environmentObject(s.builderService)
            .environmentObject(s.networkService)
            .environmentObject(s.imageService)
            .environmentObject(s.imageBuildService)
            .environmentObject(s.statsService)
            .environmentObject(s.dnsService)
            .environmentObject(s.systemService)
            .environmentObject(s.containerListService)
            .environmentObject(s.machineService)
            .environmentObject(s.clusterService)
            .environmentObject(s.modelService)
            .environmentObject(s.modelServerService)
    }
}

class MenuBarManager: ObservableObject {
    // Manager for menu bar state if needed
}
