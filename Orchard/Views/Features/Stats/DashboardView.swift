import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var statsService: StatsService
    @EnvironmentObject var systemService: SystemService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    /// Recent CPU% per container id for the table's row sparklines (last 60 samples).
    /// Recent per-metric history per container for the fleet-table sparklines.
    private var rowSparklines: [String: RowSparklines] {
        var result: [String: RowSparklines] = [:]
        for stats in statsService.containerStats {
            let samples = statsService.history.samples(for: StatsKey(id: stats.id)).suffix(60)
            result[stats.id] = RowSparklines(
                cpu: samples.map(\.cpuPercent),
                memory: samples.map(\.memoryPercent),
                network: samples.map { ($0.networkRxPerSec + $0.networkTxPerSec) / 1024 },
                disk: samples.map { ($0.blockReadPerSec + $0.blockWritePerSec) / 1024 }
            )
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
                Text("Dashboard")
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
                        sparklines: rowSparklines,
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
        let usage = systemService.systemDiskUsage
        HStack(spacing: 12) {
            statTile(icon: "shippingbox", title: "Containers",
                     value: usage?.containers.formattedSize ?? "--",
                     detail: usage.map { "\($0.containers.active)/\($0.containers.total)" } ?? "--")
            statTile(icon: "square.stack.3d.up", title: "Images",
                     value: usage?.images.formattedSize ?? "--",
                     detail: usage.map { "\($0.images.active)/\($0.images.total)" } ?? "--")
            statTile(icon: "externaldrive", title: "Volumes",
                     value: usage?.volumes.formattedSize ?? "--",
                     detail: usage.map { "\($0.volumes.active)/\($0.volumes.total)" } ?? "--")
            statTile(icon: "trash", title: "Reclaimable",
                     value: usage?.formattedTotalReclaimable ?? "--",
                     detail: "Space", valueColor: .orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statTile(icon: String, title: String, value: String, detail: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SwiftUI.Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundColor(.primary)
                Text(value)
                    .font(.subheadline).fontWeight(.semibold).fontDesign(.monospaced)
                    .foregroundColor(valueColor)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .well()
    }
}



#Preview {
    DashboardView(
        selectedTab: .constant(.dashboard),
        selectedContainer: .constant(nil)
    )
    .injectServices(AppServices())
}
