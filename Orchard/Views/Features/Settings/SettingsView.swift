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
                systemService.loadBackupExclusionState()
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
                Picker("Show Dock Icon", selection: Binding(
                    get: { settings.dockIconMode },
                    set: { mode in
                        settings.setDockIconMode(mode)
                        DockIconPolicy.apply(mode)
                    }
                )) {
                    ForEach(DockIconMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text(dockIconFooter)
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
                    Text(dnsService.unsetDomainLabel).tag("")
                    ForEach(dnsService.dnsDomains, id: \.domain) { domain in
                        Text(domain.domain).tag(domain.domain)
                    }
                }
                containerDNSDefaultRows
            } footer: {
                // A key rather than a string, so the backticks render as code as they did before.
                Text(LocalizedStringKey(dnsFooter))
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

    /// `[container.dns]` from `config.toml` (container 1.7.1), read only: every container gets
    /// these for the DNS fields it leaves empty, as with `container run`. Hidden when none are set.
    @ViewBuilder
    private var containerDNSDefaultRows: some View {
        let defaults = dnsService.containerDNSDefaults
        if let domain = dnsService.containerDefaultDomain {
            LabeledContent("Default Domain", value: domain)
        }
        if !defaults.nameservers.isEmpty {
            LabeledContent("Default Nameservers", value: defaults.nameservers.joined(separator: ", "))
        }
        if !defaults.searchDomains.isEmpty {
            LabeledContent("Default Search Domains", value: defaults.searchDomains.joined(separator: ", "))
        }
        if !defaults.options.isEmpty {
            LabeledContent("Default DNS Options", value: defaults.options.joined(separator: ", "))
        }
    }

    private var dnsFooter: String {
        var text = "The local DNS domain new containers created in Orchard get by default, so they resolve as name.domain. Compose projects brought up in Orchard use it too; `container compose` in a terminal uses container's default."
        if !dnsService.containerDNSDefaults.isEmpty {
            text += " The defaults above are set under `[container.dns]` in `~/.config/container/config.toml`, and apply to every container that doesn't set its own, as they do for `container run`. Edit that file, then restart container (`container system stop && container system start`), to change them."
        }
        if let domain = dnsService.containerDefaultDomain {
            text += " Its domain, \(domain), comes before the one chosen here."
        }
        return text
    }

    private var dockIconFooter: String {
        switch settings.dockIconMode {
        case .always:
            return "Orchard is also available from the menu bar."
        case .whileWindowsOpen:
            return "While one of its windows is open, Orchard shows its Dock icon and menu bar and can go full screen. When the last one closes, the Dock icon goes and Orchard leaves the Cmd-Tab app switcher, staying available from the menu bar."
        case .never:
            return "Orchard runs from the menu bar only and isn't in the Cmd-Tab app switcher. Its windows don't get Orchard's menu bar or go full screen, because macOS only gives those to apps with a Dock icon. Settings and Quit are in the menu bar panel."
        }
    }
}

/// Read-only `container` daemon system-properties. These are daemon state, not user
/// preferences. They're set in `~/.config/container/config.toml`; the CLI can't write them.
/// Above them, the kernel against the recommended one, and whether rebuildable data is left
/// out of Time Machine, each with the one action that fixes it.
struct SystemSettingsView: View {
    @EnvironmentObject var systemService: SystemService

    var body: some View {
        Form {
            kernelSection
            timeMachineSection
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

    // MARK: - Kernel

    /// The default kernel against the one the installed container version recommends. Only an
    /// out-of-date Kata kernel offers the switch; a custom kernel is the user's choice.
    @ViewBuilder
    private var kernelSection: some View {
        switch systemService.kernelStatus {
        case .unknown:
            EmptyView()
        case .notInstalled:
            Section {
                LabeledContent("Kernel") { Text("Not installed").foregroundStyle(.secondary) }
                useRecommendedKernelButton
            } footer: {
                Text("Containers need a kernel. The recommended one is the kernel this version of Apple container is tested with.")
                    .foregroundColor(.secondary)
            }
        case .recommended(let name):
            Section {
                LabeledContent("Kernel") { kernelName(name) }
            } footer: {
                Text("The recommended kernel for this version of Apple container.")
                    .foregroundColor(.secondary)
            }
        case .outdated(let installed, let recommended):
            Section {
                LabeledContent("Installed Kernel") { kernelName(installed) }
                LabeledContent("Recommended Kernel") { kernelName(recommended) }
                useRecommendedKernelButton
            } footer: {
                Text("The kernel installed isn't the one this version of Apple container recommends, likely because it came with an earlier version. Containers already running keep their kernel until they're restarted.")
                    .foregroundColor(.secondary)
            }
        case .custom(let name):
            Section {
                LabeledContent("Kernel") { kernelName(name) }
            } footer: {
                Text("A custom kernel, set with `container system kernel set`.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func kernelName(_ name: String) -> some View {
        Text(name)
            .font(.system(.body, design: .monospaced))
            .fontWeight(.medium)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(name)
    }

    private var useRecommendedKernelButton: some View {
        HStack {
            Spacer()
            if systemService.isKernelLoading {
                ProgressView().controlSize(.small)
            }
            Button("Use Recommended Kernel") {
                Task { await systemService.setRecommendedKernel() }
            }
            .disabled(systemService.isKernelLoading)
        }
    }

    // MARK: - Time Machine

    /// Whether `snapshots/` and `containers/` are left out of Time Machine. Shown here only, with
    /// no alert or badge, so someone who put them back in their backups isn't nagged.
    @ViewBuilder
    private var timeMachineSection: some View {
        switch systemService.backupExclusionState {
        case nil, .missing?:
            EmptyView()
        case .excluded?:
            Section {
                LabeledContent("Time Machine") { Text("Rebuildable data left out").fontWeight(.medium) }
            } footer: {
                Text("Image snapshots and container file systems aren't backed up, as they can be rebuilt by pulling the image or recreating the container. Named volumes are still backed up.")
                    .foregroundColor(.secondary)
            }
        case .included(let directories)?:
            Section {
                LabeledContent("Time Machine") {
                    Text("Backs up \(directories.joined(separator: " and "))").fontWeight(.medium)
                }
                HStack {
                    Spacer()
                    Button("Leave Out of Backups") {
                        systemService.excludeRebuildableDataFromBackups()
                    }
                }
            } footer: {
                Text("Image snapshots (`snapshots`) and container file systems (`containers`) are large and can be rebuilt by pulling the image or recreating the container, so backing them up slows Time Machine and can cost older backups. Apple container 1.7.1 leaves them out on new installs. Named volumes (`volumes`) stay backed up. Undo with `tmutil removeexclusion` on the folders in ~/Library/Application Support/com.apple.container.")
                    .foregroundColor(.secondary)
            }
        }
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
