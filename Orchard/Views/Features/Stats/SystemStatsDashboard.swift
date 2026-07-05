import SwiftUI

/// System-wide resource charts: every container's history summed tick-by-tick. CPU is a
/// total across containers (auto-scaled, since it can exceed 100%), memory is total used
/// vs total limit. Shown above the fleet table on the Stats tab.
struct SystemStatsDashboard: View {
    @EnvironmentObject var statsService: StatsService
    @EnvironmentObject var containerListService: ContainerListService
    @State private var window: StatsWindow = .fiveMin

    /// Total CPU cores reserved by running containers.
    private var reservedCores: Int {
        containerListService.containers
            .filter { $0.status.lowercased() == "running" }
            .reduce(0) { $0 + $1.configuration.resources.cpus }
    }

    /// Aggregate only the samples within the selected window, measured back from wall-clock
    /// now (not the newest sample) so a window with only stale data collapses to empty rather
    /// than summing hours-old readings as current. Keeps the summation cheap even when 24h of
    /// per-container history is retained.
    private func aggregates(now: Date) -> [StatsSample] {
        let histories = statsService.history.allSamples()
        let cutoff = now.addingTimeInterval(-window.seconds)
        let windowed = histories.map { $0.filter { $0.timestamp >= cutoff } }
        return aggregate(windowed)
    }

    var body: some View {
        let now = Date()
        let series = aggregates(now: now)
        if series.count >= 2, let latest = series.last {
            let points = chartPoints(from: series, now: now, windowSeconds: window.seconds,
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
                    .fixedSize()
                }

                // Each metric in its own half-width well: details/legend/bar above the graph.
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                              GridItem(.flexible(), alignment: .top)],
                    spacing: 12
                ) {
                    metricWell("CPU") {
                        // Summed across containers; the bar clamps at 100%.
                        MetricValueDetail(primary: "\(Int(latest.cpuPercent.rounded()))%",
                                          secondary: "\(reservedCores) \(reservedCores == 1 ? "core" : "cores") reserved",
                                          percent: latest.cpuPercent, tint: .blue)
                    } chart: {
                        cpuChart(points, windowSeconds: window.seconds, cpuDomain: nil, showLegend: false)
                    }
                    metricWell("Memory") {
                        MetricValueDetail(
                            primary: bytes(latest.memoryBytes),
                            secondary: latest.memoryLimitBytes > 0 ? "of \(bytes(latest.memoryLimitBytes))" : nil,
                            percent: latest.memoryLimitBytes > 0 ? Double(latest.memoryBytes) / Double(latest.memoryLimitBytes) * 100 : nil,
                            tint: .purple)
                    } chart: {
                        memoryChart(points, windowSeconds: window.seconds, memoryLimitBytes: latest.memoryLimitBytes, showLegend: false)
                    }
                    metricWell("Network") {
                        MetricPairDetail(top: "↓ \(rate(latest.networkRxPerSec))", topColor: .green,
                                         bottom: "↑ \(rate(latest.networkTxPerSec))", bottomColor: .orange,
                                         topRate: latest.networkRxPerSec, bottomRate: latest.networkTxPerSec)
                    } chart: {
                        networkChart(points, windowSeconds: window.seconds, showLegend: false)
                    }
                    metricWell("Disk") {
                        MetricPairDetail(top: "R \(rate(latest.blockReadPerSec))", topColor: .teal,
                                         bottom: "W \(rate(latest.blockWritePerSec))", bottomColor: .pink,
                                         topRate: latest.blockReadPerSec, bottomRate: latest.blockWritePerSec)
                    } chart: {
                        diskChart(points, windowSeconds: window.seconds, showLegend: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // A metric well for the system view: title, then details/legend/bar, then the graph.
    @ViewBuilder
    private func metricWell<Detail: View, ChartContent: View>(
        _ title: String,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder chart: () -> ChartContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundColor(.primary)
            detail()
            chart()
        }
        .well()
    }

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
    private func rate(_ perSecond: Double) -> String {
        String(format: "%.0f KB/s", perSecond / 1024)
    }
}
