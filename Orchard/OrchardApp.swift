//
//  OrchardApp.swift
//  Orchard
//
//  Created by Andrew Waters on 16/06/2025.
//

import SwiftUI

@main
struct OrchardApp: App {
    @StateObject private var containerService = ContainerService()
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(containerService)

        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Check for Updates...") {
                    Task {
                        await containerService.checkForUpdatesManually()
                    }
                }

                Divider()

                Button("Orchard Help") {
                    if let url = URL(string: "https://github.com/\(containerService.githubRepo)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(containerService)
        }

        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(containerService)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra("Orchard", systemImage: "cube.box") {
            MenuBarView()
                .environmentObject(containerService)
        }
    }
}

class MenuBarManager: ObservableObject {
    // Manager for menu bar state if needed
}

struct MenuBarView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var refreshTimer: Timer?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // System Status
            HStack {
                Circle()
                    .fill(containerService.systemStatus.color)
                    .frame(width: 8, height: 8)
                Text("Containers is \(containerService.systemStatus.text)")
            }

            Divider()

            // Container Controls
            if !containerService.containers.isEmpty {
                Menu("Containers (\(containerService.containers.count))") {
                    ForEach(containerService.containers, id: \.configuration.id) { container in
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
                            if containerService.loadingContainers.contains(
                                container.configuration.id)
                            {
                                Text("Loading...")
                                    .foregroundColor(.gray)
                            } else if container.status.lowercased() == "running" {
                                Button("Stop Container") {
                                    Task { @MainActor in
                                        await containerService.stopContainer(
                                            container.configuration.id)
                                    }
                                }
                            } else {
                                Button("Start Container") {
                                    Task { @MainActor in
                                        await containerService.startContainer(
                                            container.configuration.id)
                                    }
                                }

                                Button("Remove Container") {
                                    Task { @MainActor in
                                        await containerService.removeContainer(
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
                    await containerService.startSystem()
                }
            }
            .disabled(containerService.isSystemLoading || containerService.systemStatus == .running)

            Button("Stop") {
                Task { @MainActor in
                    await containerService.stopSystem()
                }
            }
            .disabled(containerService.isSystemLoading || containerService.systemStatus == .stopped)

            Button("Restart") {
                Task { @MainActor in
                    await containerService.restartSystem()
                }
            }
            .disabled(containerService.isSystemLoading || containerService.systemStatus == .stopped)

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
            await containerService.checkSystemStatus()
            await containerService.loadContainers(showLoading: true)
            await containerService.loadBuilders()

            await containerService.loadDNSDomains(showLoading: true)

            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onChange(of: containerService.refreshInterval) { _, _ in
            restartRefreshTimer()
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: containerService.refreshInterval.timeInterval, repeats: true) { _ in
            Task { @MainActor in
                await containerService.checkSystemStatus()
                await containerService.loadContainers(showLoading: false)
                await containerService.loadBuilders()

                await containerService.loadDNSDomains(showLoading: false)
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func restartRefreshTimer() {
        stopRefreshTimer()
        startRefreshTimer()
    }

}
