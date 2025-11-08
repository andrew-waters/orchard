import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            // Refresh Interval Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SwiftUI.Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Background Refresh Interval")
                        .font(.headline)
                        .fontWeight(.medium)
                }

                Text("How often the app should refresh container status, registry, and domain information in the background.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Picker("Refresh Interval", selection: Binding(
                        get: { containerService.refreshInterval },
                        set: { newValue in
                            containerService.setRefreshInterval(newValue)
                        }
                    )) {
                        ForEach(ContainerService.RefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)

                    Spacer()

                    HStack {
                        SwiftUI.Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Current: \(containerService.refreshInterval.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Check for Updates Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SwiftUI.Image(systemName: "arrow.down.circle")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Software Updates")
                        .font(.headline)
                        .fontWeight(.medium)
                }

                Text("Keep Orchard up to date with the latest features and improvements.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    if containerService.isCheckingForUpdates {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Checking for updates...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if containerService.updateAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SwiftUI.Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Update available: v\(containerService.latestVersion ?? "")")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                            }

                            Button("Download Update") {
                                containerService.openReleasesPage()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SwiftUI.Image(systemName: "checkmark.circle")
                                    .foregroundColor(.secondary)
                                Text("Orchard is up to date (v\(containerService.currentVersion))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Button("Check for Updates") {
                                Task {
                                    await containerService.checkForUpdates()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}

struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
            .environmentObject(ContainerService())
    }
}
