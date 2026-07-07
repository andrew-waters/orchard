import SwiftUI

/// Shared four-metric resource panel (CPU / Memory / Network / Disk) — a master–detail row
/// per metric with current values on the left and the time-series graph on the right, plus a
/// window picker. Used by both the container overview and the machine detail; callers supply
/// the data and any per-section footers (mounts, network info) so the layout and charts stay
/// identical across the two.
struct ResourceStatsPanel<NetworkFooter: View, DiskFooter: View>: View {
    let currentStats: ContainerStats?
    let currentSample: StatsSample?
    let history: [StatsSample]
    let cores: Int
    let isRunning: Bool
    let emptyMessage: String
    @ViewBuilder let networkFooter: () -> NetworkFooter
    @ViewBuilder let diskFooter: () -> DiskFooter

    @State private var window: StatsWindow = .fiveMin

    private var memoryLimitBytes: Int {
        currentStats?.memoryLimitBytes ?? currentSample?.memoryLimitBytes ?? 0
    }

    var body: some View {
        // Compute the history lookup and the chart pipeline once per render — the four metric
        // rows all plot the same series, and a single `now` keeps them time-aligned.
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
                        networkFooter()
                    }
                } chart: {
                    networkChart(points, windowSeconds: window.seconds)
                }
                MetricRow("Disk") {
                    VStack(alignment: .leading, spacing: 12) {
                        diskDetail
                        diskFooter()
                    }
                } chart: {
                    diskChart(points, windowSeconds: window.seconds)
                }
            } else {
                Text(emptyMessage)
                    .font(.callout).foregroundColor(.secondary)
                diskFooter()
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
}
