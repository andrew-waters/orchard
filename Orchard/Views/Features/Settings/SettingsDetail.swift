import SwiftUI

struct SettingsDetailView: View {
    @EnvironmentObject var containerService: ContainerService

    var body: some View {
        VStack(spacing: 0) {
            SettingsDetailHeader()

            ScrollView {
            VStack(spacing: 30) {
                // Background Refresh Setting
                HStack(alignment: .top) {
                    Text("Refresh Interval")
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

                        Text("The frequency that the app will check for updates from containers. Lower intervals increase responsiveness but add system load.")
                            .foregroundColor(.secondary)
                            .padding(.leading, 10)
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

                // System Properties Section
                VStack(spacing: 15) {
                    // Build Rosetta
                    HStack(alignment: .top) {
                        Text("Build Rosetta")
                            .frame(width: 220, alignment: .trailing)

                        VStack(alignment: .leading) {
                            TextField("", text: .constant(containerService.systemProperties.first(where: { $0.id == "build.rosetta" })?.displayValue ?? "Loading..."))
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
                            let currentDomain = containerService.systemProperties.first(where: { $0.id == "dns.domain" })?.value ?? ""
                            Picker("", selection: Binding(
                                get: { currentDomain },
                                set: { newValue in
                                    DispatchQueue.main.async {
                                        Task {
                                            await containerService.setSystemProperty("dns.domain", value: newValue)
                                        }
                                    }
                                }
                            )) {
                                ForEach(containerService.dnsDomains, id: \.domain) { domain in
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
                            TextField("", text: .constant(containerService.systemProperties.first(where: { $0.id == "image.builder" })?.value ?? "Loading..."))
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
                            TextField("", text: .constant(containerService.systemProperties.first(where: { $0.id == "image.init" })?.value ?? "Loading..."))
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
                            TextField("", text: .constant(containerService.systemProperties.first(where: { $0.id == "kernel.binaryPath" })?.value ?? "Loading..."))
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
                            TextField("", text: .constant(containerService.systemProperties.first(where: { $0.id == "kernel.url" })?.value ?? "Loading..."))
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
                            TextField("", text: .constant(containerService.systemProperties.first(where: { $0.id == "registry.domain" })?.value ?? "Loading..."))
                                .textFieldStyle(.plain)
                                .fontWeight(.medium)
                            Text("The default registry to use for image references that do not specify a registry.")
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }

                    Spacer(minLength: 20)
                }
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await containerService.loadSystemProperties()
            }
        }
    }
}
