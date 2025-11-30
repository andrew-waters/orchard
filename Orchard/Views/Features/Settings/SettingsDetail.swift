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

                Spacer()
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
