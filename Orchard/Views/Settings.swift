import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "general"
        case dns = "dns"
        case registries = "registries"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .registries: return "Registries"
            case .dns: return "DNS"
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .registries: return "server.rack"
            case .dns: return "network"
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
                    case .dns:
                        dnsSettings
                    case .registries:
                        registrySettings
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

    private var registrySettings: some View {
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


    // MARK: - DNS Settings

    private var dnsSettings: some View {
        VStack(spacing: 20) {
            if containerService.isDNSLoading {
                HStack {
                    Spacer()
                    VStack {
                        ProgressView()
                        Text("Loading DNS domains...")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 200)
            } else if containerService.dnsDomains.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        SwiftUI.Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No DNS Domains")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Add a DNS domain to enable local container networking.\nThis requires administrator privileges.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Add your first domain") {
                            showAddDNSDomainSheet()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .frame(minHeight: 200)
            } else {
                VStack(spacing: 12) {
                    ForEach(containerService.dnsDomains) { domain in
                        HStack {
                            Text("\(domain.domain):")
                                .frame(width: 220, alignment: .trailing)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(domain.domain)
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(domain.isDefault ? .semibold : .medium)

                                        if domain.isDefault {
                                            SwiftUI.Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                        }
                                    }

                                    if domain.isDefault {
                                        Text("Default Domain")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    if domain.isDefault {
                                        Button("Unset Default") {
                                            Task { await containerService.unsetDefaultDNSDomain() }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    } else {
                                        Button("Set Default") {
                                            Task { await containerService.setDefaultDNSDomain(domain.domain) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Button("Delete") {
                                        confirmDNSDomainDeletion(domain: domain.domain)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }

            if !containerService.dnsDomains.isEmpty {
                HStack {
                    Text("")
                        .frame(width: 220, alignment: .trailing)

                    HStack {
                        Button("Add Domain") {
                            showAddDNSDomainSheet()
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()
        }
    }

    // MARK: - Dialog Methods

    private func showAddDNSDomainSheet() {
        let alert = NSAlert()
        alert.messageText = "Add DNS Domain"
        alert.informativeText = "Enter a domain name for local container networking. This requires administrator privileges."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "e.g., local.dev, myapp.local"
        alert.accessoryView = textField

        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let domain = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !domain.isEmpty, isValidDomainName(domain) else {
                containerService.errorMessage = "Invalid domain name format."
                return
            }

            Task { await containerService.createDNSDomain(domain) }
        }
    }

    private func confirmDNSDomainDeletion(domain: String) {
        let alert = NSAlert()
        alert.messageText = "Delete DNS Domain"
        alert.informativeText = "Are you sure you want to delete '\(domain)'? This requires administrator privileges."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await containerService.deleteDNSDomain(domain) }
        }
    }

    private func isValidDomainName(_ domain: String) -> Bool {
        let regex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.[a-zA-Z0-9]+$"
        return domain.range(of: regex, options: .regularExpression) != nil
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
