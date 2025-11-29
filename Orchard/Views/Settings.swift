import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "general"
        case registries = "registries"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .registries: return "Registries"
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .registries: return "server.rack"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar with tabs
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    VStack(spacing: 4) {
                        SwiftUI.Image(systemName: tab.systemImage)
                            .font(.system(size: 16))
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)

                        Text(tab.title)
                            .font(.caption)
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }
                    .frame(minWidth: 80, minHeight: 60)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTab = tab
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content area
            ScrollView {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .general:
                        generalSettings
                    case .registries:
                        registriesSettings
                    }
                }
                .padding(.top, 30)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 800, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Error", isPresented: .constant(containerService.errorMessage != nil)) {
            Button("OK") {
                containerService.errorMessage = nil
            }
        } message: {
            Text(containerService.errorMessage ?? "")
        }
        .alert("Success", isPresented: .constant(containerService.successMessage != nil)) {
            Button("OK") {
                containerService.successMessage = nil
            }
        } message: {
            Text(containerService.successMessage ?? "")
        }
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        VStack(spacing: 20) {
            // Background Refresh Setting
            HStack(alignment: .top) {
                Text("Refresh Interval:")
                    .frame(width: 220, alignment: .trailing)
                    .padding(.top, 4)

                VStack(alignment: .leading) {
                    Picker("", selection: Binding(
                        get: { containerService.refreshInterval },
                        set: { containerService.setRefreshInterval($0) }
                    )) {
                        ForEach(ContainerService.RefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200, alignment: .leading)

                    Text("The frequency that the app will check for updates from cotnainers. Lower intervals increase responsiveness but add system load.")
                        .foregroundColor(.secondary)
                        .padding(.leading, 10)
                }

                Spacer()
            }

            // Software Updates Section
            VStack(spacing: 15) {
                HStack(alignment: .top) {
                    Text("Updates:")
                        .frame(width: 220, alignment: .trailing)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        if containerService.isCheckingForUpdates {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking for updates...")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 10)
                            }
                        } else if containerService.updateAvailable {
                            Button("Download Update") {
                                containerService.openReleasesPage()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Text("Update available: v\(containerService.latestVersion ?? "")")
                                .foregroundColor(.green)
                                .padding(.leading, 10)

                        } else {
                            Button("Check for Updates") {
                                Task { await containerService.checkForUpdates() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Text("Orchard is up to date (v\(containerService.currentVersion))")
                                .foregroundColor(.secondary)
                                .padding(.leading, 10)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()
        }
    }

    // MARK: - Registry Settings

    private var registriesSettings: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Registries cannot be listed due to limitations with container itself. To add them, you'll need to open a terminal and run the container commands. Copy your registry password to your clipboard and run:")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("pbpaste | container registry login REGISTRY_URL --username YOUR_USERNAME --password-stdin")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("pbpaste | container registry login REGISTRY_URL --username YOUR_USERNAME --password-stdin", forType: .string)
                            }) {
                                SwiftUI.Image(systemName: "doc.on.clipboard")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy command to clipboard")
                        }
                    }
                }
                Spacer()
            }
            .frame(minHeight: 200)

            Spacer()
        }
    }


    private func createLabel(text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        return label
    }
}

#Preview {
    SettingsView()
        .environmentObject(ContainerService())
}
