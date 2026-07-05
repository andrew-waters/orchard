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
/// gap segment. Age is measured from wall-clock `now` (not the newest sample) so stale or
/// stopped data draws where it actually falls on the axis — a stopped container's last point
/// sits back from the "now" edge and reads as a gap, rather than masquerading as current.
/// Segments are computed over the *visible* samples so a window-dropped head never leaves a
/// false leading gap.
func buildTimeline(_ timestamps: [Date], now: Date, windowSeconds: Double, gapThreshold: Double) -> [TimelinePoint] {
    var result: [TimelinePoint] = []
    var segment = 0
    var previousVisible: Date?
    for (i, ts) in timestamps.enumerated() {
        let age = now.timeIntervalSince(ts)
        guard age >= 0, age <= windowSeconds else { continue }
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
func chartPoints(from samples: [StatsSample], now: Date, windowSeconds: Double, gapThreshold: Double) -> [ChartPoint] {
    let visible = samples.filter { now.timeIntervalSince($0.timestamp) <= windowSeconds }
    let reduced = downsample(visible, to: chartPointTarget)

    return buildTimeline(reduced.map(\.timestamp), now: now, windowSeconds: windowSeconds, gapThreshold: gapThreshold).map { tp in
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
/// A gap wider than this means sampling paused or the container restarted — break the line.
/// Based on the idle cadence and scaled to the window so downsampled long views don't read
/// every (naturally wide) step as a gap.
func statsGapThreshold(windowSeconds: Double) -> Double {
    let expectedSpacing = windowSeconds / Double(chartPointTarget)
    return max(StatsService.idleInterval * 2.5, expectedSpacing * 2.5)
}

private func autoUpper(_ series: [SeriesPoint]) -> Double {
    max((series.map(\.y).max() ?? 0) * 1.2, 1)
}

// Per-metric chart builders, so the container overview and system dashboard render identical
// charts while composing their own detail columns around them.

func cpuChart(_ points: [ChartPoint], windowSeconds: Double, cpuDomain: ClosedRange<Double>?, showLegend: Bool = true) -> MetricChart {
    let series = points.map { SeriesPoint(x: $0.secondsAgo, y: $0.cpuPercent, series: "cpu\($0.segment)", label: "CPU") }
    return MetricChart(series: series, windowSeconds: windowSeconds,
                       yDomain: cpuDomain ?? 0...autoUpper(series), palette: [("CPU", .blue)], unit: "%",
                       showLegend: showLegend)
}

func memoryChart(_ points: [ChartPoint], windowSeconds: Double, memoryLimitBytes: Int, showLegend: Bool = true) -> MetricChart {
    let series = points.map { SeriesPoint(x: $0.secondsAgo, y: $0.memoryMB, series: "mem\($0.segment)", label: "Memory") }
    let limitMB = Double(memoryLimitBytes) / 1_048_576
    let maxMem = series.map(\.y).max() ?? 0
    let upper = limitMB > 0 ? max(limitMB, maxMem) * 1.05 : max(maxMem * 1.2, 1)
    return MetricChart(series: series, windowSeconds: windowSeconds, yDomain: 0...upper,
                       palette: [("Memory", .purple)], unit: "MB",
                       fill: true, ruleY: limitMB > 0 ? limitMB : nil, ruleLabel: "Limit", showLegend: showLegend)
}

/// Symmetric domain for a mirrored (in above / out below) chart.
private func mirroredDomain(_ series: [SeriesPoint]) -> ClosedRange<Double> {
    let maxAbs = max((series.map { abs($0.y) }.max() ?? 0) * 1.2, 1)
    return -maxAbs...maxAbs
}

func networkChart(_ points: [ChartPoint], windowSeconds: Double, showLegend: Bool = true) -> MetricChart {
    // Rx above the axis, Tx below — in MB/s.
    let series = points.flatMap {
        [SeriesPoint(x: $0.secondsAgo, y: $0.netRxKBs / 1024, series: "rx\($0.segment)", label: "Rx"),
         SeriesPoint(x: $0.secondsAgo, y: -$0.netTxKBs / 1024, series: "tx\($0.segment)", label: "Tx")]
    }
    return MetricChart(series: series, windowSeconds: windowSeconds, yDomain: mirroredDomain(series),
                       palette: [("Rx", .green), ("Tx", .orange)], unit: "MB/s", mirrored: true, showLegend: showLegend)
}

func diskChart(_ points: [ChartPoint], windowSeconds: Double, showLegend: Bool = true) -> MetricChart {
    // Read above the axis, Write below.
    let series = points.flatMap {
        [SeriesPoint(x: $0.secondsAgo, y: $0.blockReadKBs, series: "read\($0.segment)", label: "Read"),
         SeriesPoint(x: $0.secondsAgo, y: -$0.blockWriteKBs, series: "write\($0.segment)", label: "Write")]
    }
    return MetricChart(series: series, windowSeconds: windowSeconds, yDomain: mirroredDomain(series),
                       palette: [("Read", .teal), ("Write", .pink)], unit: "KB/s", mirrored: true, showLegend: showLegend)
}

/// Shared style for the primary stat values, so every metric reads the same.
extension View {
    func metricValueText() -> some View {
        font(.subheadline).fontWeight(.semibold).fontDesign(.monospaced)
    }

    /// Standard inset "well" used to box each section on the detail page. Uses a translucent
    /// tint plus a hairline border so it stays distinct from the pane background in both
    /// light and dark, regardless of what that background happens to be.
    func well() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

/// Left detail cell: a capacity bar directly under the header, then a big primary value and
/// an optional caption.
struct MetricValueDetail: View {
    let primary: String
    var secondary: String? = nil
    var percent: Double? = nil
    var tint: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let percent { ProgressView(value: min(1, max(0, percent / 100))).tint(tint) }
            Text(primary).metricValueText()
            if let secondary {
                Text(secondary).font(.caption).foregroundColor(.secondary).fontDesign(.monospaced)
            }
        }
    }
}

/// Left detail cell: two color-dotted values (e.g. Rx/Tx or Read/Write) and, when current
/// rates are supplied, a center-split directional bar (left = inbound/top, right = outbound/bottom).
struct MetricPairDetail: View {
    let top: String
    let topColor: Color
    let bottom: String
    let bottomColor: Color
    var topRate: Double? = nil
    var bottomRate: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if topRate != nil || bottomRate != nil {
                DirectionalBar(leftValue: topRate ?? 0, rightValue: bottomRate ?? 0,
                               leftColor: topColor, rightColor: bottomColor)
            }
            HStack(spacing: 16) {
                value(top, topColor)
                value(bottom, bottomColor)
            }
        }
    }

    private func value(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).metricValueText()
        }
    }
}

/// A center-origin activity bar: fills leftward for the inbound value and rightward for the
/// outbound value, each normalized to the larger of the two so the busier direction fills its
/// half. A center tick marks zero activity.
struct DirectionalBar: View {
    let leftValue: Double
    let rightValue: Double
    let leftColor: Color
    let rightColor: Color

    var body: some View {
        Canvas { context, size in
            let mid = size.width / 2
            let height = size.height
            let maxValue = max(leftValue, rightValue, 0.0001)

            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: height)),
                         with: .color(Color(NSColor.tertiaryLabelColor).opacity(0.3)))

            let leftWidth = CGFloat(min(1, max(0, leftValue) / maxValue)) * mid
            if leftWidth > 0 {
                context.fill(Path(CGRect(x: mid - leftWidth, y: 0, width: leftWidth, height: height)),
                             with: .color(leftColor))
            }
            let rightWidth = CGFloat(min(1, max(0, rightValue) / maxValue)) * mid
            if rightWidth > 0 {
                context.fill(Path(CGRect(x: mid, y: 0, width: rightWidth, height: height)),
                             with: .color(rightColor))
            }

            var center = Path()
            center.move(to: CGPoint(x: mid, y: 0))
            center.addLine(to: CGPoint(x: mid, y: height))
            context.stroke(center, with: .color(Color(NSColor.separatorColor)), lineWidth: 1)
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

/// One master–detail metric row: a header, a details column (≈1/3) beside its graph (≈2/3),
/// and an optional footer rendered directly beneath the graph (e.g. mounts, network config).
struct MetricRow<Detail: View, ChartContent: View, Footer: View>: View {
    let title: String
    let detail: Detail
    let chart: ChartContent
    let footer: Footer

    init(_ title: String,
         @ViewBuilder detail: () -> Detail,
         @ViewBuilder chart: () -> ChartContent,
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.detail = detail()
        self.chart = chart()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.headline).foregroundColor(.primary)
            HStack(alignment: .top, spacing: 16) {
                detail
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 0)
                VStack(alignment: .leading, spacing: 12) {
                    chart
                    footer
                }
                .frame(maxWidth: .infinity)
            }
        }
        .well()
    }
}

/// A compact, axis-less line used inside the fleet table rows. Fills its column width and
/// auto-scales unless `maxValue` is given (e.g. 100 for a percentage).
struct Sparkline: View {
    let values: [Double]
    var color: Color = .blue
    var maxValue: Double? = nil

    var body: some View {
        if values.count < 2 {
            Color.clear.frame(height: 18)
        } else {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("i", index), y: .value("v", value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...(maxValue ?? max(values.max() ?? 1, 0.0001)))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 18)
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
    /// Mirror mode: the second series is plotted negative (below the axis). Labels/tooltips
    /// show absolute values and a zero baseline is drawn.
    var mirrored: Bool = false
    /// Whether the chart draws its own legend (off when a legend is shown above the graph).
    var showLegend: Bool = true

    @State private var selectedX: Double?

    private var uniqueXs: [Double] { Array(Set(series.map(\.x))).sorted() }

    private func nearestX(to x: Double) -> Double? {
        uniqueXs.min(by: { abs($0 - x) < abs($1 - x) })
    }

    private func format(_ value: Double) -> String {
        let magnitude = mirrored ? abs(value) : value
        let number = magnitude >= 100 ? String(format: "%.0f", magnitude) : String(format: "%.1f", magnitude)
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

            if mirrored {
                RuleMark(y: .value("Zero", 0))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary)
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
        .chartLegend(showLegend && palette.count > 1 ? .visible : .hidden)
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
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yAxisLabel(v))
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

    // Absolute magnitude for mirrored charts; one decimal when the range is small (e.g. MB/s).
    private func yAxisLabel(_ v: Double) -> String {
        let magnitude = mirrored ? abs(v) : v
        let span = yDomain.upperBound - yDomain.lowerBound
        return span < 20 ? String(format: "%.1f", magnitude) : "\(Int(magnitude))"
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
