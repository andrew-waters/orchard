import SwiftUI

@main
struct OrchardApp: App {
    @StateObject private var services = AppServices.forLaunch()
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var updater = UpdaterService()

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



        WindowGroup(id: "logs") {
            MultiLogView()
                .injectServices(services)
        }
        .defaultSize(width: 900, height: 600)
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra("Orchard", systemImage: "cube.box") {
            MenuBarView()
                .injectServices(services)
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
    }
}

class MenuBarManager: ObservableObject {
    // Manager for menu bar state if needed
}

struct MenuBarView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var builderService: BuilderService
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var dnsService: DNSService
    @EnvironmentObject var networkService: NetworkService
    @State private var refreshTimer: Timer?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // System Status
            HStack {
                Circle()
                    .fill(systemService.systemStatus.color)
                    .frame(width: 8, height: 8)
                Text("Containers is \(systemService.systemStatus.text)")
            }

            Divider()

            // Container Controls
            if !containerListService.containers.isEmpty {
                Menu("Containers (\(containerListService.containers.count))") {
                    ForEach(containerListService.containers, id: \.configuration.id) { container in
                        Menu {
                            // Container status
                            HStack {
                                Circle()
                                    .fill(
                                        container.status.lowercased() == "running" ? .green : .gray
                                    )
                                    .frame(width: 8, height: 8)
                                Text("Status: \(container.status)")
                            }
                            .foregroundColor(.secondary)

                            Divider()

                            // Copy IP address
                            if !container.networks.isEmpty {
                                Button("Copy IP Address") {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    let ipAddress = container.networks[0].address
                                        .replacingOccurrences(of: "/24", with: "")
                                    pasteboard.setString(ipAddress, forType: .string)
                                }
                            }

                            // Start/Stop container
                            if containerListService.loadingContainers.contains(
                                container.configuration.id)
                            {
                                Text("Loading...")
                                    .foregroundColor(.gray)
                            } else if container.status.lowercased() == "running" {
                                Button("Stop Container") {
                                    Task { @MainActor in
                                        await containerListService.stopContainer(
                                            container.configuration.id)
                                    }
                                }
                            } else {
                                Button("Start Container") {
                                    Task { @MainActor in
                                        await containerListService.startContainer(
                                            container.configuration.id)
                                    }
                                }

                                Button("Remove Container") {
                                    Task { @MainActor in
                                        await containerListService.removeContainer(
                                            container.configuration.id)
                                    }
                                }
                            }
                        } label: {
                            Label {
                                Text(container.configuration.id)
                            } icon: {
                                Circle()
                                    .fill(
                                        container.status.lowercased() == "running" ? .green : .gray
                                    )
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }

                Divider()
            }

            // System Controls
            Button("Start") {
                Task { @MainActor in
                    await systemService.startSystem()
                }
            }
            .disabled(systemService.isSystemLoading || systemService.systemStatus == .running)

            Button("Stop") {
                Task { @MainActor in
                    await systemService.stopSystem()
                }
            }
            .disabled(systemService.isSystemLoading || systemService.systemStatus == .stopped)

            Button("Restart") {
                Task { @MainActor in
                    await systemService.restartSystem()
                }
            }
            .disabled(systemService.isSystemLoading || systemService.systemStatus == .stopped)

            Divider()

            Button("Open Main Window") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("Quit Orchard") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 200)
        .task {
            await systemService.checkSystemStatus()
            await containerListService.loadContainers(showLoading: true)
            await builderService.loadBuilders()

            await dnsService.load(showLoading: true)
            await networkService.load(showLoading: true)
            await systemService.loadSystemDiskUsage(showLoading: false)

            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                await systemService.checkSystemStatus()
                await containerListService.loadContainers(showLoading: false)
                await builderService.loadBuilders()
                await dnsService.load(showLoading: false)
                await networkService.load(showLoading: false)
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

}
