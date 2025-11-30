import SwiftUI

struct SettingsDetailView: View {
    @EnvironmentObject var containerService: ContainerService

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
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

                        Text("The frequency that the app will check for updates from containers. Lower intervals increase responsiveness but add system load.")
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

                // System Properties Section
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top) {
                        Text("System Properties:")
                            .frame(width: 220, alignment: .trailing)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if containerService.isSystemPropertiesLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Loading properties...")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 10)
                                } else {
                                    Button("Refresh Properties") {
                                        Task { await containerService.loadSystemProperties() }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            if !containerService.systemProperties.isEmpty {
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], alignment: .leading, spacing: 12) {
                                    ForEach(containerService.systemProperties) { property in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(property.id)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .fontWeight(.medium)

                                                Text(property.type.displayName)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.1))
                                                    .cornerRadius(4)

                                                Spacer()
                                            }

                                            Text(property.displayValue)
                                                .font(.caption)
                                                .foregroundColor(property.isUndefined ? .secondary : .primary)
                                                .padding(.bottom, 2)

                                            Text(property.description)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.05))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding(.top, 8)
                            } else if !containerService.isSystemPropertiesLoading {
                                Text("No system properties available. Try refreshing.")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await containerService.loadSystemProperties()
            }
        }
    }
}
