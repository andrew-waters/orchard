import SwiftUI

/// System-wide resource charts: every container's history summed tick-by-tick. CPU is a
/// total across containers (auto-scaled, since it can exceed 100%), memory is total used
/// vs total limit. Shown above the fleet table on the Stats tab.
struct SystemStatsDashboard: View {
    @EnvironmentObject var statsService: StatsService
    @EnvironmentObject var containerListService: ContainerListService
    @State private var window: StatsWindow = .fiveMin
    /// Memoizes the last aggregate fold so a body re-eval that isn't a new tick (or window
    /// change) reuses it instead of re-summing the whole window.
    @StateObject private var cache = AggregateCache()

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
        let newest = histories.compactMap { $0.last?.timestamp }.max()
        // Keyed on (window, latest tick): between ticks `now` advances but the fold barely
        // changes, so reusing the last result is correct enough and skips the re-fold.
        let key = "\(window.rawValue)|\(newest?.timeIntervalSinceReferenceDate ?? -1)"
        if let hit = cache.entry(for: key) { return hit }

        let cutoff = now.addingTimeInterval(-window.seconds)
        let windowed = histories.map { $0.filter { $0.timestamp >= cutoff } }
        let result = aggregate(windowed)
        cache.store(result, for: key)
        return result
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
                        MetricPairDetail(top: "↓ \(networkRate(latest.networkRxPerSec))", topColor: .green,
                                         bottom: "↑ \(networkRate(latest.networkTxPerSec))", bottomColor: .orange,
                                         topRate: latest.networkRxPerSec, bottomRate: latest.networkTxPerSec)
                    } chart: {
                        networkChart(points, windowSeconds: window.seconds, showLegend: false)
                    }
                    metricWell("Disk") {
                        MetricPairDetail(top: "R \(diskRate(latest.blockReadPerSec))", topColor: .teal,
                                         bottom: "W \(diskRate(latest.blockWritePerSec))", bottomColor: .pink,
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
        ByteFormat.memory(value)
    }
    // Rate text matches each chart's own axis unit so the current value and the graph read the
    // same: networkChart plots MB/s, diskChart plots KB/s.
    private func networkRate(_ perSecond: Double) -> String {
        String(format: "%.1f MB/s", perSecond / 1_048_576)
    }
    private func diskRate(_ perSecond: Double) -> String {
        String(format: "%.0f KB/s", perSecond / 1024)
    }
}

/// Single-entry cache for `SystemStatsDashboard`'s aggregate fold. An `ObservableObject` with
/// no published state so mutating it during `body` never triggers a re-render loop; it just
/// persists the last (key, value) across body evaluations.
private final class AggregateCache: ObservableObject {
    private var key: String?
    private var cached: [StatsSample] = []

    func entry(for key: String) -> [StatsSample]? {
        self.key == key ? cached : nil
    }

    func store(_ value: [StatsSample], for key: String) {
        self.key = key
        cached = value
    }
}
