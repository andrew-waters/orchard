import SwiftUI

@main
struct OrchardApp: App {
    @NSApplicationDelegateAdaptor(OrchardAppDelegate.self) private var appDelegate
    @StateObject private var services: AppServices
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var updater = UpdaterService()

    init() {
        let services = AppServices.forLaunch()
        _services = StateObject(wrappedValue: services)
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
            CommandGroup(replacing: .help) {
                CheckForUpdatesView(updater: updater)

                Divider()

                Button("Orchard Help") {
                    if let url = URL(string: "https://github.com/andrew-waters/orchard") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }



        WindowGroup(id: "logs", for: LogTarget.self) { $target in
            MultiLogView(initialTarget: target)
                .injectServices(services)
        }
        .defaultSize(width: 900, height: 600)
        .windowToolbarStyle(.unified(showsTitle: false))

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
            .environmentObject(s.statsService)
            .environmentObject(s.dnsService)
            .environmentObject(s.systemService)
            .environmentObject(s.containerListService)
            .environmentObject(s.startupSequenceService)
            .environmentObject(s.machineService)
            .environmentObject(s.modelService)
            .environmentObject(s.modelServerService)
    }
}

class MenuBarManager: ObservableObject {
    // Manager for menu bar state if needed
}
