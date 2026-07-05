import SwiftUI

/// Per-container resource view: a master–detail row per metric (current values on the left,
/// the time-series graph on the right). Mounts render beneath the disk stats; network config
/// lives in its own section on the page. Embeds inside the container overview.
struct ContainerStatsPanel: View {
    let container: Container
    @EnvironmentObject var statsService: StatsService
    @State private var window: StatsWindow = .fiveMin

    private var id: String { container.configuration.id }
    private var isRunning: Bool { container.status.lowercased() == "running" }
    private var cores: Int { container.configuration.resources.cpus }
    private var currentStats: ContainerStats? { statsService.containerStats.first { $0.id == id } }
    private var currentSample: StatsSample? { statsService.latestSamples[id] }
    private var history: [StatsSample] { statsService.history.samples(for: StatsKey(id: id)) }
    private var mounts: [Mount] { container.configuration.mounts }

    private var memoryLimitBytes: Int {
        currentStats?.memoryLimitBytes ?? currentSample?.memoryLimitBytes ?? 0
    }
    var body: some View {
        // Compute the history lookup and the chart pipeline once per render — the four metric
        // rows all plot the same series, and a single `now` keeps them time-aligned.
        let history = history
        let points = chartPoints(from: history, now: Date(), windowSeconds: window.seconds,
                                 gapThreshold: statsGapThreshold(windowSeconds: window.seconds))
        return VStack(alignment: .leading, spacing: 12) {
            header

            if isRunning || !history.isEmpty {
                MetricRow("CPU") { cpuDetail } chart: {
                    cpuChart(points, windowSeconds: window.seconds, cpuDomain: 0...100)
                }
                MetricRow("Memory") { memoryDetail } chart: {
                    memoryChart(points, windowSeconds: window.seconds, memoryLimitBytes: memoryLimitBytes)
                }
                MetricRow("Network") {
                    VStack(alignment: .leading, spacing: 12) {
                        networkDetail
                        networkInfoFooter
                    }
                } chart: {
                    networkChart(points, windowSeconds: window.seconds)
                }
                MetricRow("Disk") {
                    VStack(alignment: .leading, spacing: 12) {
                        diskDetail
                        mountsFooter
                    }
                } chart: {
                    diskChart(points, windowSeconds: window.seconds)
                }
            } else {
                Text("No statistics — the container is not running.")
                    .font(.callout).foregroundColor(.secondary)
                if !mounts.isEmpty { mountsFooter }
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack {
            Spacer()
            Picker("", selection: $window) {
                ForEach(StatsWindow.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: detail columns

    @ViewBuilder private var cpuDetail: some View {
        if isRunning, let cpu = currentSample?.cpuPercent {
            MetricValueDetail(primary: String(format: "%.1f%%", cpu),
                              secondary: cores > 0 ? "\(cores) \(cores == 1 ? "core" : "cores") allocated" : nil,
                              percent: cpu, tint: .blue)
        } else {
            notRunning
        }
    }

    @ViewBuilder private var memoryDetail: some View {
        if isRunning, let stats = currentStats {
            MetricValueDetail(
                primary: stats.formattedMemoryUsage,
                secondary: "\(stats.formattedMemoryLimit) allocated",
                percent: stats.memoryUsagePercent, tint: .purple)
        } else {
            notRunning
        }
    }

    @ViewBuilder private var networkDetail: some View {
        if isRunning, let stats = currentStats {
            MetricPairDetail(top: "↓ \(stats.formattedNetworkRx)", topColor: .green,
                             bottom: "↑ \(stats.formattedNetworkTx)", bottomColor: .orange,
                             topRate: currentSample?.networkRxPerSec, bottomRate: currentSample?.networkTxPerSec)
        } else {
            notRunning
        }
    }

    @ViewBuilder private var diskDetail: some View {
        if isRunning, let stats = currentStats {
            MetricPairDetail(top: "R \(stats.formattedBlockRead)", topColor: .teal,
                             bottom: "W \(stats.formattedBlockWrite)", bottomColor: .pink,
                             topRate: currentSample?.blockReadPerSec, bottomRate: currentSample?.blockWritePerSec)
        } else {
            notRunning
        }
    }

    private var notRunning: some View {
        Text(isRunning ? "--" : "Not running")
            .font(.title3).fontWeight(.semibold).fontDesign(.monospaced)
            .foregroundColor(.secondary)
    }

    // MARK: network info (beneath the network graph)

    @ViewBuilder private var networkInfoFooter: some View {
        if !container.networks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Info").font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                ForEach(container.networks, id: \.hostname) { network in
                    let cleanHostname = network.hostname.hasSuffix(".") ? String(network.hostname.dropLast()) : network.hostname
                    CopyableInfoRow(label: "Hostname", value: cleanHostname, copyValue: cleanHostname)
                    CopyableInfoRow(
                        label: "Address",
                        value: network.address,
                        copyValue: network.address.strippingCIDRSuffix
                    )
                }
            }
        }
    }

    // MARK: mounts (beneath the disk graph)

    @ViewBuilder private var mountsFooter: some View {
        if !mounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mounts").font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                ForEach(Array(mounts.enumerated()), id: \.offset) { _, mount in
                    Button {
                        // Navigate to the mount detail view (ContainerMount.id is source->dest).
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToMount"),
                            object: "\(mount.source)->\(mount.destination)")
                    } label: {
                        Text(mount.destination).font(.subheadline).fontDesign(.monospaced)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}
