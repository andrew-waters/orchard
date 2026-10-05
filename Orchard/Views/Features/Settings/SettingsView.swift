import AppKit
import SwiftUI

/// The app's native `Settings` scene (⌘,). A `TabView` of preference panes: General for
/// genuine app preferences, System for read-only `container` daemon properties. Adding a
/// pane (e.g. Telemetry) is a one-line `.tabItem` away.
struct SettingsView: View {
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var dnsService: DNSService

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            SystemSettingsView()
                .tabItem {
                    Label("System", systemImage: "cpu")
                }
        }
        .frame(width: 540, height: 460)
        // Loaded once here rather than per-tab: macOS TabView builds both tabs when the
        // window opens, so a per-tab onAppear would fetch the property list twice.
        .onAppear {
            Task {
                await systemService.loadSystemProperties(showLoading: true)
                await dnsService.load(showLoading: true)
            }
        }
    }
}

/// Genuine app preferences: which terminal to open shells in, which `container` binary to
/// drive, the default DNS domain, and software updates.
struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var alertCenter: AlertCenter
    @EnvironmentObject var updater: UpdaterService
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var dnsService: DNSService

    /// Edited as it is typed, so the field is not fighting the store on every keystroke.
    @State private var containerShell: String = ""

    var body: some View {
        Form {
            Section {
                Picker("Terminal Application", selection: Binding(
                    get: { settings.preferredTerminal },
                    set: { settings.setPreferredTerminal($0) }
                )) {
                    ForEach(settings.installedTerminals, id: \.self) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }
            } footer: {
                Text("The terminal application to use when opening a shell into a container.")
                    .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Container Shell") {
                    TextField(
                        SettingsStore.defaultContainerShell,
                        text: $containerShell,
                        prompt: Text(SettingsStore.defaultContainerShell)
                    )
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 220)
                    .onSubmit { settings.setContainerShell(containerShell) }
                    .onChange(of: containerShell) { _, value in settings.setContainerShell(value) }
                }
            } footer: {
                Text("Run inside the container when opening a terminal, flags included: \(SettingsStore.defaultContainerShell) by default, or something like bash -l to have login shells read your rc files. Leave empty to reset.")
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Hide Dock icon", isOn: Binding(
                    get: { settings.hideDockIcon },
                    set: { hidden in
                        settings.setHideDockIcon(hidden)
                        DockIconPolicy.apply(hidden: hidden)
                    }
                ))
            } footer: {
                Text("Orchard stays available from the menu bar. Hiding the Dock icon also removes Orchard from the Cmd-Tab app switcher; reopen the main window from the menu bar.")
                    .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Container Binary") {
                    HStack(spacing: 8) {
                        Text(settings.containerBinaryPath)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            panel.showsHiddenFiles = true
                            panel.treatsFilePackagesAsDirectories = true
                            if panel.runModal() == .OK, let url = panel.url {
                                if !settings.validateAndSetCustomBinaryPath(url.path) {
                                    alertCenter.error("Selected file is not an executable: \(url.path)")
                                }
                            }
                        }
                        .controlSize(.small)
                        .fixedSize()

                        if settings.isUsingCustomBinary {
                            Button("Reset") {
                                settings.resetToDefaultBinary()
                            }
                            .controlSize(.small)
                            .fixedSize()
                        }
                    }
                }
            } footer: {
                Text("Path to the `container` CLI. Auto-detected from common locations (Homebrew, Nix, /usr/local); override if your binary lives elsewhere.")
                    .foregroundColor(.secondary)
            }

            Section {
                // An Orchard preference: the CLI can no longer write the daemon's `dns.domain`
                // (#116). The "" row means none chosen in Orchard, so the daemon's own default
                // applies if `config.toml` sets one. `systemService` is observed so that row's
                // label follows the daemon's value.
                Picker("DNS Domain", selection: Binding(
                    get: { settings.defaultDNSDomain ?? "" },
                    set: { dnsService.setDefault($0.isEmpty ? nil : $0) }
                )) {
                    Text(dnsService.daemonDefaultDomain().map { "container default (\($0))" } ?? "None").tag("")
                    ForEach(dnsService.dnsDomains, id: \.domain) { domain in
                        Text(domain.domain).tag(domain.domain)
                    }
                }
            } footer: {
                Text("The local DNS domain new containers created in Orchard get by default, so they resolve as name.domain.")
                    .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Updates") {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .controlSize(.small)
                    .disabled(!updater.canCheckForUpdates)
                }
            } footer: {
                Text("You're running Orchard v\(AppInfo.version). Orchard checks for updates automatically.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { containerShell = settings.containerShell }
    }
}

/// Read-only `container` daemon system-properties. These are daemon state, not user
/// preferences. They're set in `~/.config/container/config.toml`; the CLI can't write them.
struct SystemSettingsView: View {
    @EnvironmentObject var systemService: SystemService

    var body: some View {
        Form {
            daemonProperty(
                title: "Build Rosetta",
                propertyId: "build.rosetta",
                useDisplayValue: true,
                description: "Build amd64 images on arm64 using Rosetta, instead of QEMU."
            )
            daemonProperty(
                title: "Image Builder",
                propertyId: "image.builder",
                monospaced: true,
                description: "The image reference for the utility container that `container build` uses."
            )
            daemonProperty(
                title: "Image Init",
                propertyId: "image.init",
                monospaced: true,
                description: "The image reference for the default initial filesystem image."
            )
            daemonProperty(
                title: "Kernel Binary Path",
                propertyId: "kernel.binaryPath",
                monospaced: true,
                description: "If the kernel URL is for an archive, the archive member pathname for the kernel file."
            )
            daemonProperty(
                title: "Kernel URL",
                propertyId: "kernel.url",
                monospaced: true,
                description: "The URL for the kernel file to install, or the URL for an archive containing the kernel file."
            )
            daemonProperty(
                title: "Registry Domain",
                propertyId: "registry.domain",
                description: "The default registry to use for image references that do not specify a registry."
            )
        }
        .formStyle(.grouped)
    }

    /// A read-only daemon property row: label, its value (from `systemProperties`), and a
    /// footnote description. `useDisplayValue` reads `displayValue` (human-formatted) rather
    /// than the raw value.
    private func daemonProperty(
        title: String,
        propertyId: String,
        useDisplayValue: Bool = false,
        monospaced: Bool = false,
        description: String
    ) -> some View {
        let property = systemService.systemProperties.first(where: { $0.id == propertyId })
        let value = (useDisplayValue ? property?.displayValue : property?.value) ?? "Loading..."
        return Section {
            LabeledContent(title) {
                Text(value)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value)
            }
        } footer: {
            Text(description)
                .foregroundColor(.secondary)
        }
    }
}
