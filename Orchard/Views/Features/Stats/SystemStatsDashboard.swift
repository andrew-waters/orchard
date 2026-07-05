import SwiftUI

/// System-wide resource charts: every container's history summed tick-by-tick. CPU is a
/// total across containers (auto-scaled, since it can exceed 100%), memory is total used
/// vs total limit. Shown above the fleet table on the Stats tab.
struct SystemStatsDashboard: View {
    @EnvironmentObject var statsService: StatsService
    @State private var window: StatsWindow = .fiveMin

    /// Aggregate only the samples within the selected window — keeps the summation cheap
    /// even when 24h of per-container history is retained.
    private var aggregates: [StatsSample] {
        let histories = statsService.history.allSamples()
        guard let newest = histories.compactMap({ $0.last?.timestamp }).max() else { return [] }
        let cutoff = newest.addingTimeInterval(-window.seconds)
        let windowed = histories.map { $0.filter { $0.timestamp >= cutoff } }
        return aggregate(windowed)
    }

    var body: some View {
        let series = aggregates
        if series.count >= 2, let latest = series.last {
            let points = chartPoints(from: series, windowSeconds: window.seconds,
                                     gapThreshold: statsGapThreshold(windowSeconds: window.seconds))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("System")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Picker("", selection: $window) {
                        ForEach(StatsWindow.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                MetricRow("CPU") {
                    // Summed across containers, so it can exceed 100% — no capacity bar.
                    MetricValueDetail(primary: "\(Int(latest.cpuPercent.rounded()))%", tint: .blue)
                } chart: {
                    cpuChart(points, windowSeconds: window.seconds, cpuDomain: nil)
                }
                MetricRow("Memory") {
                    MetricValueDetail(
                        primary: bytes(latest.memoryBytes),
                        secondary: latest.memoryLimitBytes > 0 ? "of \(bytes(latest.memoryLimitBytes))" : nil,
                        percent: latest.memoryLimitBytes > 0 ? Double(latest.memoryBytes) / Double(latest.memoryLimitBytes) * 100 : nil,
                        tint: .purple)
                } chart: {
                    memoryChart(points, windowSeconds: window.seconds, memoryLimitBytes: latest.memoryLimitBytes)
                }
                MetricRow("Network") {
                    MetricPairDetail(top: "↓ \(rate(latest.networkRxPerSec))", topColor: .green,
                                     bottom: "↑ \(rate(latest.networkTxPerSec))", bottomColor: .orange,
                                     topRate: latest.networkRxPerSec, bottomRate: latest.networkTxPerSec)
                } chart: {
                    networkChart(points, windowSeconds: window.seconds)
                }
                MetricRow("Disk") {
                    MetricPairDetail(top: "R \(rate(latest.blockReadPerSec))", topColor: .teal,
                                     bottom: "W \(rate(latest.blockWritePerSec))", bottomColor: .pink,
                                     topRate: latest.blockReadPerSec, bottomRate: latest.blockWritePerSec)
                } chart: {
                    diskChart(points, windowSeconds: window.seconds)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
    private func rate(_ perSecond: Double) -> String {
        String(format: "%.0f KB/s", perSecond / 1024)
    }
}
