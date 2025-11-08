import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "general"
        case registries = "registries"
        case dns = "dns"

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
                    case .registries:
                        registrySettings
                    case .dns:
                        dnsSettings
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
                HStack {
                    Text("Software Updates:")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 8) {
                        if containerService.isCheckingForUpdates {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking for updates...")
                                    .foregroundColor(.secondary)
                            }
                        } else if containerService.updateAvailable {
                            Text("Update available: v\(containerService.latestVersion ?? "")")
                                .foregroundColor(.green)

                            Button("Download Update") {
                                containerService.openReleasesPage()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Text("Orchard is up to date (v\(containerService.currentVersion))")
                                .foregroundColor(.secondary)

                            Button("Check for Updates") {
                                Task { await containerService.checkForUpdates() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
            if containerService.isRegistriesLoading {
                HStack {
                    Spacer()
                    VStack {
                        ProgressView()
                        Text("Loading registries...")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 200)
            } else if containerService.registries.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        SwiftUI.Image(systemName: "server.rack")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Registries")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Add a registry login to pull images from private repositories.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Add Registry") {
                            showRegistryLoginSheet()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .frame(minHeight: 200)
            } else {
                VStack(spacing: 12) {
                    ForEach(containerService.registries) { registry in
                        HStack {
                            Text("\(registry.server):")
                                .frame(width: 220, alignment: .trailing)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(registry.server)
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(registry.isDefault ? .semibold : .medium)

                                        if registry.isDefault {
                                            SwiftUI.Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                        }
                                    }

                                    if let username = registry.username {
                                        Text("User: \(username)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    if registry.isDefault {
                                        Text("Default Registry")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    if registry.isDefault {
                                        Button("Unset Default") {
                                            Task { await containerService.unsetDefaultRegistry() }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    } else {
                                        Button("Set Default") {
                                            Task { await containerService.setDefaultRegistry(registry.server) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Button("Logout") {
                                        confirmRegistryLogout(registry: registry.server)
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

            HStack {
                Text("")
                    .frame(width: 220, alignment: .trailing)

                HStack {
                    Button("Add Registry") {
                        showRegistryLoginSheet()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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

                        Button("Add First Domain") {
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

            Spacer()
        }
    }

    // MARK: - Dialog Methods

    private func showRegistryLoginSheet() {
        let alert = NSAlert()
        alert.messageText = "Registry Login"
        alert.informativeText = "Login to a container registry to access private repositories."
        alert.alertStyle = .informational

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))

        let serverField = NSTextField(frame: NSRect(x: 0, y: 90, width: 400, height: 24))
        serverField.placeholderString = "docker.io, ghcr.io, registry.example.com"

        let usernameField = NSTextField(frame: NSRect(x: 0, y: 60, width: 400, height: 24))
        usernameField.placeholderString = "Username"

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 400, height: 24))
        passwordField.placeholderString = "Password or token"

        view.addSubview(createLabel(text: "Server:", frame: NSRect(x: 0, y: 110, width: 100, height: 20)))
        view.addSubview(serverField)
        view.addSubview(createLabel(text: "Username:", frame: NSRect(x: 0, y: 80, width: 100, height: 20)))
        view.addSubview(usernameField)
        view.addSubview(createLabel(text: "Password:", frame: NSRect(x: 0, y: 50, width: 100, height: 20)))
        view.addSubview(passwordField)

        alert.accessoryView = view
        alert.addButton(withTitle: "Login")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let server = serverField.stringValue.trimmingCharacters(in: .whitespaces)
            let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
            let password = passwordField.stringValue

            guard !server.isEmpty, !username.isEmpty, !password.isEmpty else {
                containerService.errorMessage = "Please fill in all fields."
                return
            }

            let request = RegistryLoginRequest(
                server: server,
                username: username,
                password: password,
                scheme: .auto
            )

            Task { await containerService.loginToRegistry(request) }
        }
    }

    private func confirmRegistryLogout(registry: String) {
        let alert = NSAlert()
        alert.messageText = "Registry Logout"
        alert.informativeText = "Are you sure you want to logout from '\(registry)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Logout")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await containerService.logoutFromRegistry(registry) }
        }
    }

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
        let regex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$"
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
