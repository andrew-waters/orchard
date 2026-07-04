import Charts
import SwiftUI

/// Selectable chart window. `seconds` is the visible x-range; `retention` is how much
/// history the store must hold to fill it.
enum StatsWindow: String, CaseIterable, Identifiable {
    case fiveMin = "5m"
    case fifteenMin = "15m"
    case hour = "1h"
    case day = "24h"

    var id: String { rawValue }

    var seconds: Double {
        switch self {
        case .fiveMin: return 300
        case .fifteenMin: return 900
        case .hour: return 3600
        case .day: return 86_400
        }
    }
}

/// One plotted point. `series` groups points a line connects (encodes the gap segment so
/// lines don't span sampling pauses); `label` is the color/legend group (e.g. "Rx"/"Tx").
struct SeriesPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let series: String
    let label: String
}

/// A visible sample's position on the time axis. Pure output of `buildTimeline`.
struct TimelinePoint {
    let index: Int          // index into the source sample array
    let secondsAgo: Double  // 0 = newest, negative = older
    let segment: Int        // increments across a sampling gap
}

/// Pure: clip timestamps to the window and assign each visible sample its seconds-ago and
/// gap segment. Segments are computed over the *visible* samples so a window-dropped head
/// never leaves a false leading gap.
func buildTimeline(_ timestamps: [Date], windowSeconds: Double, gapThreshold: Double) -> [TimelinePoint] {
    guard let newest = timestamps.last else { return [] }
    var result: [TimelinePoint] = []
    var segment = 0
    var previousVisible: Date?
    for (i, ts) in timestamps.enumerated() {
        let age = newest.timeIntervalSince(ts)
        guard age <= windowSeconds else { continue }
        if let previous = previousVisible, ts.timeIntervalSince(previous) > gapThreshold {
            segment += 1
        }
        previousVisible = ts
        result.append(TimelinePoint(index: i, secondsAgo: -age, segment: segment))
    }
    return result
}

/// Pure: bucket-average a sample series down to at most `target` points so long windows
/// (1h/24h) stay cheap to render. Averaging smooths spikes slightly; acceptable at these
/// zoom levels. Returns the input unchanged when it already fits.
func downsample(_ samples: [StatsSample], to target: Int) -> [StatsSample] {
    guard target > 0, samples.count > target else { return samples }
    let bucketSize = Int((Double(samples.count) / Double(target)).rounded(.up))
    var result: [StatsSample] = []
    var i = 0
    while i < samples.count {
        let bucket = samples[i..<min(i + bucketSize, samples.count)]
        result.append(average(bucket))
        i += bucketSize
    }
    return result
}

private func average(_ bucket: ArraySlice<StatsSample>) -> StatsSample {
    let n = Double(bucket.count)
    func mean(_ path: (StatsSample) -> Double) -> Double { bucket.reduce(0) { $0 + path($1) } / n }
    // Timestamp: the bucket's last, so the newest bucket still lands at "now".
    return StatsSample(
        timestamp: bucket.last!.timestamp,
        cpuPercent: mean(\.cpuPercent),
        memoryBytes: Int(mean { Double($0.memoryBytes) }),
        memoryLimitBytes: bucket.last!.memoryLimitBytes,
        networkRxPerSec: mean(\.networkRxPerSec),
        networkTxPerSec: mean(\.networkTxPerSec),
        blockReadPerSec: mean(\.blockReadPerSec),
        blockWritePerSec: mean(\.blockWritePerSec),
        pids: Int(mean { Double($0.pids) })
    )
}

/// Target points per chart after downsampling — keeps 1h/24h cheap to render.
let chartPointTarget = 400

/// One plotted sample across all four metrics, positioned on the time axis.
struct ChartPoint {
    let secondsAgo: Double
    let segment: Int
    let cpuPercent: Double
    let memoryMB: Double
    let netRxKBs: Double
    let netTxKBs: Double
    let blockReadKBs: Double
    let blockWriteKBs: Double
}

/// Pure: window-clip, downsample, and position a sample series for charting. Works for a
/// single container's history or an aggregated system-wide series (both are `[StatsSample]`).
func chartPoints(from samples: [StatsSample], windowSeconds: Double, gapThreshold: Double) -> [ChartPoint] {
    guard let newest = samples.last else { return [] }
    let visible = samples.filter { newest.timestamp.timeIntervalSince($0.timestamp) <= windowSeconds }
    let reduced = downsample(visible, to: chartPointTarget)

    return buildTimeline(reduced.map(\.timestamp), windowSeconds: windowSeconds, gapThreshold: gapThreshold).map { tp in
        let s = reduced[tp.index]
        return ChartPoint(
            secondsAgo: tp.secondsAgo,
            segment: tp.segment,
            cpuPercent: s.cpuPercent,
            memoryMB: Double(s.memoryBytes) / 1_048_576,
            netRxKBs: s.networkRxPerSec / 1024,
            netTxKBs: s.networkTxPerSec / 1024,
            blockReadKBs: s.blockReadPerSec / 1024,
            blockWriteKBs: s.blockWritePerSec / 1024
        )
    }
}

/// The four stacked metric charts (CPU / Memory / Network / Disk) for a sample series.
/// Shared by the per-container overview and the system dashboard; they differ only in the
/// CPU y-scale (fixed 0…100 for one container, auto for summed totals).
struct StatsChartsGrid: View {
    let samples: [StatsSample]
    let memoryLimitBytes: Int
    let windowSeconds: Double
    /// Fixed CPU y-domain; nil auto-scales (system totals exceed 100%).
    var cpuDomain: ClosedRange<Double>? = 0...100

    private var gapThreshold: Double {
        // Idle cadence is the coarsest normal spacing; also scaled to the window so a
        // downsampled long view doesn't read every (naturally wide) step as a gap.
        let expectedSpacing = windowSeconds / Double(chartPointTarget)
        return max(StatsService.idleInterval * 2.5, expectedSpacing * 2.5)
    }

    private var points: [ChartPoint] {
        chartPoints(from: samples, windowSeconds: windowSeconds, gapThreshold: gapThreshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartSection("CPU", unit: "%") {
                let pts = points.map { SeriesPoint(x: $0.secondsAgo, y: $0.cpuPercent, series: "cpu\($0.segment)", label: "CPU") }
                MetricChart(series: pts, windowSeconds: windowSeconds,
                            yDomain: cpuDomain ?? 0...autoUpper(pts), palette: [("CPU", .blue)], unit: "%")
            }

            chartSection("Memory", unit: "MB") {
                let mem = points.map { SeriesPoint(x: $0.secondsAgo, y: $0.memoryMB, series: "mem\($0.segment)", label: "Memory") }
                let limitMB = Double(memoryLimitBytes) / 1_048_576
                let maxMem = mem.map(\.y).max() ?? 0
                let upper = limitMB > 0 ? max(limitMB, maxMem) * 1.05 : max(maxMem * 1.2, 1)
                MetricChart(series: mem, windowSeconds: windowSeconds, yDomain: 0...upper,
                            palette: [("Memory", .purple)], unit: "MB",
                            fill: true, ruleY: limitMB > 0 ? limitMB : nil, ruleLabel: "Limit")
            }

            chartSection("Network", unit: "KB/s") {
                let net = points.flatMap {
                    [SeriesPoint(x: $0.secondsAgo, y: $0.netRxKBs, series: "rx\($0.segment)", label: "Rx"),
                     SeriesPoint(x: $0.secondsAgo, y: $0.netTxKBs, series: "tx\($0.segment)", label: "Tx")]
                }
                MetricChart(series: net, windowSeconds: windowSeconds, yDomain: 0...autoUpper(net),
                            palette: [("Rx", .green), ("Tx", .orange)], unit: "KB/s")
            }

            chartSection("Disk", unit: "KB/s") {
                let disk = points.flatMap {
                    [SeriesPoint(x: $0.secondsAgo, y: $0.blockReadKBs, series: "read\($0.segment)", label: "Read"),
                     SeriesPoint(x: $0.secondsAgo, y: $0.blockWriteKBs, series: "write\($0.segment)", label: "Write")]
                }
                MetricChart(series: disk, windowSeconds: windowSeconds, yDomain: 0...autoUpper(disk),
                            palette: [("Read", .teal), ("Write", .pink)], unit: "KB/s")
            }
        }
    }

    private func autoUpper(_ series: [SeriesPoint]) -> Double {
        max((series.map(\.y).max() ?? 0) * 1.2, 1)
    }

    @ViewBuilder
    private func chartSection<Content: View>(_ title: String, unit: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(unit).font(.caption).foregroundColor(.secondary)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// A compact, axis-less CPU line used inside the fleet table rows.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .blue

    var body: some View {
        if values.count < 2 {
            Color.clear.frame(width: 80, height: 24)
        } else {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("i", index), y: .value("cpu", value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(width: 80, height: 24)
        }
    }
}

/// A single metric's line chart: one or more series, fixed or auto y-scale, an optional
/// limit rule-line, an adaptive time axis, and hover-to-read tooltips.
struct MetricChart: View {
    let series: [SeriesPoint]
    let windowSeconds: Double
    let yDomain: ClosedRange<Double>
    let palette: [(String, Color)]
    let unit: String
    var fill: Bool = false
    var ruleY: Double? = nil
    var ruleLabel: String = ""

    @State private var selectedX: Double?

    private var uniqueXs: [Double] { Array(Set(series.map(\.x))).sorted() }

    private func nearestX(to x: Double) -> Double? {
        uniqueXs.min(by: { abs($0 - x) < abs($1 - x) })
    }

    private func format(_ value: Double) -> String {
        let number = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    var body: some View {
        if series.count < 2 {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.5)
                Text("Collecting…").font(.caption).foregroundColor(.secondary)
            }
            .frame(height: 140, alignment: .center)
            .frame(maxWidth: .infinity)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { p in
                if fill {
                    AreaMark(x: .value("Time", p.x), y: .value("Value", p.y), series: .value("Series", p.series))
                        .foregroundStyle(by: .value("Metric", p.label))
                        .opacity(0.25)
                        .interpolationMethod(.monotone)
                }
                LineMark(x: .value("Time", p.x), y: .value("Value", p.y), series: .value("Series", p.series))
                    .foregroundStyle(by: .value("Metric", p.label))
                    .interpolationMethod(.monotone)
            }

            if let ruleY {
                RuleMark(y: .value("Limit", ruleY))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text(ruleLabel).font(.caption2).foregroundColor(.secondary)
                    }
            }

            if let selectedX, let nearest = nearestX(to: selectedX) {
                RuleMark(x: .value("Selected", nearest))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .annotation(
                        position: .top,
                        alignment: .center,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        tooltip(at: nearest)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: -windowSeconds...0)
        .chartForegroundStyleScale(domain: palette.map(\.0), range: palette.map(\.1))
        .chartLegend(palette.count > 1 ? .visible : .hidden)
        .chartXSelection(value: $selectedX)
        .chartXAxis {
            AxisMarks(values: .stride(by: axisStride)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(axisLabel(seconds))
                    }
                }
            }
        }
        .frame(height: 140)
    }

    private func tooltip(at x: Double) -> some View {
        let hits = series.filter { $0.x == x }
        return VStack(alignment: .leading, spacing: 2) {
            Text(axisLabel(x) == "now" ? "now" : "\(axisLabel(x)) ago")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(hits) { hit in
                HStack(spacing: 4) {
                    Circle()
                        .fill(palette.first { $0.0 == hit.label }?.1 ?? .primary)
                        .frame(width: 6, height: 6)
                    if palette.count > 1 {
                        Text(hit.label).font(.caption2).foregroundColor(.secondary)
                    }
                    Text(format(hit.y)).font(.caption2).fontDesign(.monospaced)
                }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    // Adaptive axis: minute ticks for short windows, hour ticks for the day view.
    private var axisStride: Double {
        switch windowSeconds {
        case ...300: return 60       // 5m → every minute
        case ...900: return 180      // 15m → every 3 minutes
        case ...3600: return 600     // 1h → every 10 minutes
        default: return 10_800       // 24h → every 3 hours
        }
    }

    private func axisLabel(_ seconds: Double) -> String {
        if seconds == 0 { return "now" }
        let ago = -seconds
        if windowSeconds > 3600 { return "\(Int((ago / 3600).rounded()))h" }
        return "\(Int((ago / 60).rounded()))m"
    }
}
