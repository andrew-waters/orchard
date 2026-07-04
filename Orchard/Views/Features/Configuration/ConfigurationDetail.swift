import AppKit
import SwiftUI

struct ConfigurationDetailView: View {
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var dnsService: DNSService
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var alertCenter: AlertCenter
    @EnvironmentObject var updater: UpdaterService

    var body: some View {
        VStack(spacing: 0) {
            ConfigurationDetailHeader()

            ScrollView {
            VStack(spacing: 30) {
                // Terminal Application Setting
                HStack(alignment: .top) {
                    Text("Terminal Application")
                        .frame(width: 220, alignment: .trailing)
                        .padding(.top, 4)

                    VStack(alignment: .leading) {
                        Picker("", selection: Binding(
                            get: { settings.preferredTerminal },
                            set: { settings.setPreferredTerminal($0) }
                        )) {
                            ForEach(settings.installedTerminals, id: \.self) { terminal in
                                Text(terminal.displayName).tag(terminal)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200, alignment: .leading)

                        Text("The terminal application to use when opening a shell into a container.")
                            .foregroundColor(.secondary)
                            .padding(.leading, 10)

                    }

                    Spacer()
                }

                // Container Binary
                HStack(alignment: .top) {
                    Text("Container Binary")
                        .frame(width: 220, alignment: .trailing)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.containerBinaryPath)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
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

                            if settings.isUsingCustomBinary {
                                Button("Reset to Auto-detect") {
                                    settings.resetToDefaultBinary()
                                }
                                .controlSize(.small)
                            }
                        }

                        Text("Path to the `container` CLI. Auto-detected from common locations (Homebrew, Nix, /usr/local); override if your binary lives elsewhere.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Software Updates Section
                VStack(spacing: 15) {
                    HStack(alignment: .top) {
                        Text("Updates")
                            .frame(width: 220, alignment: .trailing)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            Button("Check for Updates…") {
                                updater.checkForUpdates()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!updater.canCheckForUpdates)

                            Text("You're running Orchard v\(AppInfo.version). Orchard checks for updates automatically.")
                                .foregroundColor(.secondary)
                                .padding(.leading, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Build Rosetta
                HStack(alignment: .top) {
                    Text("Build Rosetta")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading) {
                        TextField("", text: .constant(systemService.systemProperties.first(where: { $0.id == "build.rosetta" })?.displayValue ?? "Loading..."))
                            .textFieldStyle(.plain)
                            .fontWeight(.medium)
                        Text("Build amd64 images on arm64 using Rosetta, instead of QEMU.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // DNS Domain
                HStack(alignment: .top) {
                    Text("DNS Domain")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading) {
                        let currentDomain = systemService.systemProperties.first(where: { $0.id == "dns.domain" })?.value ?? ""
                        Picker("", selection: Binding(
                            get: { currentDomain },
                            set: { newValue in
                                DispatchQueue.main.async {
                                    Task {
                                        await systemService.setSystemProperty("dns.domain", value: newValue)
                                    }
                                }
                            }
                        )) {
                            ForEach(dnsService.dnsDomains, id: \.domain) { domain in
                                Text(domain.domain).tag(domain.domain)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200, alignment: .leading)

                        Text("If defined, the local DNS domain to use for containers with unqualified names.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Image Builder
                HStack(alignment: .top) {
                    Text("Image Builder")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading) {
                        TextField("", text: .constant(systemService.systemProperties.first(where: { $0.id == "image.builder" })?.value ?? "Loading..."))
                            .textFieldStyle(.plain)
                            .fontWeight(.medium)
                            .font(.system(.body, design: .monospaced))
                        Text("The image reference for the utility container that `container build` uses.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Image Init
                HStack(alignment: .top) {
                    Text("Image Init")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading) {
                        TextField("", text: .constant(systemService.systemProperties.first(where: { $0.id == "image.init" })?.value ?? "Loading..."))
                            .textFieldStyle(.plain)
                            .fontWeight(.medium)
                            .font(.system(.body, design: .monospaced))
                        Text("The image reference for the default initial filesystem image.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Kernel Binary Path
                HStack(alignment: .top) {
                    Text("Kernel Binary Path")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading) {
                        TextField("", text: .constant(systemService.systemProperties.first(where: { $0.id == "kernel.binaryPath" })?.value ?? "Loading..."))
                            .textFieldStyle(.plain)
                            .fontWeight(.medium)
                            .font(.system(.body, design: .monospaced))
                        Text("If the kernel URL is for an archive, the archive member pathname for the kernel file.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Kernel URL
                HStack(alignment: .top) {
                    Text("Kernel URL")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading) {
                        TextField("", text: .constant(systemService.systemProperties.first(where: { $0.id == "kernel.url" })?.value ?? "Loading..."))
                            .textFieldStyle(.plain)
                            .fontWeight(.medium)
                            .font(.system(.body, design: .monospaced))
                        Text("The URL for the kernel file to install, or the URL for an archive containing the kernel file.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Registry Domain
                HStack(alignment: .top) {
                    Text("Registry Domain")
                        .frame(width: 220, alignment: .trailing)

                    VStack(alignment: .leading) {
                        TextField("", text: .constant(systemService.systemProperties.first(where: { $0.id == "registry.domain" })?.value ?? "Loading..."))
                            .textFieldStyle(.plain)
                            .fontWeight(.medium)
                        Text("The default registry to use for image references that do not specify a registry.")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                    Spacer(minLength: 20)
                }
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await systemService.loadSystemProperties(showLoading: true)
                await dnsService.load(showLoading: true)
            }
        }
    }
}
