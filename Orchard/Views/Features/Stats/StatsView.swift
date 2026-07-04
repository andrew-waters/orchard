import SwiftUI

struct StatsView: View {
    @EnvironmentObject var statsService: StatsService
    @EnvironmentObject var systemService: SystemService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    /// Recent CPU% per container id for the table's row sparklines (last 60 samples).
    private var cpuSparklines: [String: [Double]] {
        var result: [String: [Double]] = [:]
        for stats in statsService.containerStats {
            result[stats.id] = statsService.history
                .samples(for: StatsKey(id: stats.id))
                .suffix(60)
                .map(\.cpuPercent)
        }
        return result
    }

    private var emptyMessage: String {
        if statsService.isStatsLoading {
            return "Loading container statistics..."
        } else if statsService.containerStats.isEmpty {
            return "No running containers or stats unavailable"
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Stats")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Passive, non-modal notice when the daemon can't return stats — the 1s
            // poll intentionally does not raise an alert for this.
            if statsService.statsUnavailable {
                HStack(spacing: 8) {
                    SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stats Unavailable")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Running containers were found but no statistics came back — check that the container service is up to date and running.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Stats table
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // System Disk Usage Section
                    SystemDiskUsageView()

                    // System-wide resource charts (aggregate of all containers)
                    SystemStatsDashboard()

                    Text("Container Utilisation")
                        .font(.headline)
                        .foregroundColor(.primary)

                    // Container Stats Table
                    StatsTableView(
                        containerStats: statsService.containerStats,
                        latestSamples: statsService.latestSamples,
                        sparklines: cpuSparklines,
                        selectedTab: $selectedTab,
                        selectedContainer: $selectedContainer,
                        emptyStateMessage: emptyMessage,
                        showContainerColumn: true
                    )
                }
                .padding(16)
            }
        }
        .onAppear {
            Task {
                await statsService.load(showLoading: true)
                await systemService.loadSystemDiskUsage(showLoading: true)
            }
            // The service owns sampling now (2s cadence), so history keeps accumulating
            // across view switches. Disk usage changes slowly — refreshed on appear only.
            statsService.beginSampling()
        }
        .onDisappear {
            statsService.endSampling()
        }
    }
}

// MARK: - System Disk Usage View

struct SystemDiskUsageView: View {
    @EnvironmentObject var systemService: SystemService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Disk Usage")
                .font(.headline)
                .foregroundColor(.primary)

            if let diskUsage = systemService.systemDiskUsage {
                HStack(spacing: 16) {
                    // Containers
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Containers")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.containers.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                        Text("\(diskUsage.containers.active)/\(diskUsage.containers.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Images
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Images")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.images.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                        Text("\(diskUsage.images.active)/\(diskUsage.images.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Volumes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volumes")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.volumes.formattedSize)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                        Text("\(diskUsage.volumes.active)/\(diskUsage.volumes.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Reclaimable
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reclaimable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(diskUsage.formattedTotalReclaimable)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.orange)
                        Text("Space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            } else {
                HStack(spacing: 16) {
                    // Containers placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Containers")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Images placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Images")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Volumes placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volumes")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Reclaimable placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reclaimable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundColor(.secondary)
                        Text("Space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}



#Preview {
    StatsView(
        selectedTab: .constant(.stats),
        selectedContainer: .constant(nil)
    )
    .injectServices(AppServices())
}
