import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var statsService: StatsService
    @EnvironmentObject var systemService: SystemService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    /// Slow refresh for the disk-usage tiles while the Dashboard is on screen. `system df`
    /// is heavier than a per-container stats read, so this stays well below the 2s sampling
    /// cadence — enough to catch a pull/prune/remove without hammering the daemon.
    @State private var diskRefreshTimer: Timer?
    private static let diskRefreshInterval: TimeInterval = 20

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

    /// Recent per-metric history per machine id for the machine table's row sparklines.
    private var machineSparklines: [String: RowSparklines] {
        var result: [String: RowSparklines] = [:]
        for stats in statsService.machineStats {
            let samples = statsService.machineHistory(stats.id).suffix(60)
            result[stats.id] = RowSparklines(
                cpu: samples.map(\.cpuPercent),
                memory: samples.map(\.memoryPercent),
                network: samples.map { ($0.networkRxPerSec + $0.networkTxPerSec) / 1024 },
                disk: samples.map { ($0.blockReadPerSec + $0.blockWritePerSec) / 1024 }
            )
        }
        return result
    }

    /// Latest derived sample per machine id (re-keyed from the namespaced sampling key), so
    /// the shared stats table can read machine CPU% the same way it reads containers'.
    private var machineLatestSamples: [String: StatsSample] {
        Dictionary(uniqueKeysWithValues: statsService.machineStats.compactMap { stats in
            statsService.machineSample(stats.id).map { (stats.id, $0) }
        })
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
                    SystemDiskUsageView(selectedTab: $selectedTab)

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

                    // Machine Utilisation (only when machines are reporting stats)
                    if !statsService.machineStats.isEmpty {
                        Text("Machine Utilisation")
                            .font(.headline)
                            .foregroundColor(.primary)

                        StatsTableView(
                            containerStats: statsService.machineStats,
                            latestSamples: machineLatestSamples,
                            sparklines: machineSparklines,
                            selectedTab: $selectedTab,
                            selectedContainer: $selectedContainer,
                            emptyStateMessage: "",
                            showContainerColumn: true,
                            nameColumnTitle: "Machine",
                            rowIcon: "cpu",
                            rowIconColor: .blue,
                            onSelectRow: { id in
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("NavigateToMachine"), object: id)
                            }
                        )
                    }
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
            // across view switches.
            statsService.beginSampling()
            startDiskRefresh()
        }
        .onDisappear {
            statsService.endSampling()
            stopDiskRefresh()
        }
    }

    /// Re-fetch disk usage on a slow cadence while visible so the tiles don't go stale during
    /// image pulls/prunes. `.common` mode keeps it firing through scroll/menu tracking.
    private func startDiskRefresh() {
        diskRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.diskRefreshInterval, repeats: true) { _ in
            Task { @MainActor in await systemService.loadSystemDiskUsage(showLoading: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        diskRefreshTimer = timer
    }

    private func stopDiskRefresh() {
        diskRefreshTimer?.invalidate()
        diskRefreshTimer = nil
    }
}

// MARK: - System Disk Usage View

struct SystemDiskUsageView: View {
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var diskPurgeService: DiskPurgeService
    /// The Volumes tile opens the Volumes tab.
    @Binding var selectedTab: TabSelection
    @State private var showFreeUpSpace = false

    var body: some View {
        let usage = systemService.systemDiskUsage
        VStack(alignment: .leading, spacing: 8) {
            Text("Disk Usage")
                .font(.headline)
                .foregroundColor(.primary)
            tiles(usage, systemService.diskUsageBreakdown)
        }
        .sheet(isPresented: $showFreeUpSpace) {
            FreeUpSpaceView()
        }
    }

    /// The breakdown's figures where there is one, otherwise the runtime's own, with System
    /// and Reclaimable left blank since only the breakdown can say them.
    private func tiles(_ usage: SystemDiskUsage?, _ breakdown: DiskUsageBreakdown?) -> some View {
        let containers = breakdown?.containers ?? usage?.containers
        let images = breakdown?.images ?? usage?.images
        let volumes = breakdown?.volumes ?? usage?.volumes
        return HStack(spacing: 12) {
            statTile(icon: "shippingbox", title: "Containers",
                     value: containers?.formattedSize ?? "--",
                     detail: containers.map { "\($0.active)/\($0.total)" } ?? "--")
            statTile(icon: "square.stack.3d.up", title: "Images",
                     value: images?.formattedSize ?? "--",
                     detail: images.map { "\($0.active)/\($0.total)" } ?? "--")
            Button { selectedTab = .volumes } label: {
                statTile(icon: TabSelection.volumes.icon, title: "Volumes",
                         value: volumes?.formattedSize ?? "--",
                         detail: volumes.map { "\($0.active)/\($0.total)" } ?? "--")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show volumes")
            .accessibilityIdentifier("dashboard-volumes")
            statTile(icon: "gearshape", title: "System",
                     value: breakdown.map { Self.bytes($0.systemSize) } ?? "--",
                     detail: breakdown.map(Self.systemDetail) ?? "--")
                .help("The image builder and the images the runtime needs to start containers. Free Up Space leaves these alone.")
            statTile(icon: "trash", title: "Reclaimable",
                     value: breakdown.map { Self.bytes($0.reclaimable) } ?? "--",
                     valueColor: .orange) {
                Button("Free Up Space...") {
                    // Before presenting, so the sheet's first frame isn't last time's list.
                    diskPurgeService.reset()
                    showFreeUpSpace = true
                }
                .buttonStyle(.link)
                // No usage means the runtime isn't answering, so there's nothing to list.
                .disabled(usage == nil)
                .help("Remove images, stopped containers and volumes that aren't in use")
                .accessibilityIdentifier("free-up-space")
            }
                .help("What Free Up Space can remove with every section switched on. This is less than container system df reports, since that also counts the builder, system images, and stopped machines, compose services and sandboxes.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .binary)
    }

    private static func systemDetail(_ breakdown: DiskUsageBreakdown) -> String {
        var parts: [String] = []
        if breakdown.systemContainers > 0 {
            parts.append(breakdown.systemContainers == 1 ? "1 builder" : "\(breakdown.systemContainers) builders")
        }
        if breakdown.systemImages > 0 {
            parts.append(breakdown.systemImages == 1 ? "1 image" : "\(breakdown.systemImages) images")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }

    private func statTile(icon: String, title: String, value: String, detail: String, valueColor: Color = .primary) -> some View {
        statTile(icon: icon, title: title, value: value, valueColor: valueColor) {
            Text(detail).foregroundColor(.secondary)
        }
    }

    /// Every tile has the same three lines, so they line up: a title, a figure, and a caption
    /// line that is usually text but can be a control. Each stays on one line rather than
    /// wrapping when the tiles are narrow.
    private func statTile<Detail: View>(
        icon: String, title: String, value: String, valueColor: Color = .primary,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
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
                detail().font(.caption)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
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
