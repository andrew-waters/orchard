import AppKit
import SwiftUI

/// Window-style menu-bar panel: two segmented resource rings (CPU / memory across running
/// containers), a per-container breakdown with start/stop controls, and system controls.
struct MenuBarView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var builderService: BuilderService
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var startupSequenceService: StartupSequenceService
    @EnvironmentObject var dnsService: DNSService
    @EnvironmentObject var networkService: NetworkService
    @EnvironmentObject var statsService: StatsService
    @State private var refreshTimer: Timer?
    @State private var hoveringTop = false
    @State private var hoveredContainer: String?
    @Environment(\.openWindow) private var openWindow

    /// Distinct colors assigned to containers by memory rank; shared by the rings and list.
    private static let palette: [Color] = [.blue, .purple, .green, .orange, .teal, .pink, .yellow, .indigo, .mint, .cyan]
    private var freeColor: Color { Color(NSColor.tertiaryLabelColor) }

    private struct Row: Identifiable {
        let id: String
        let color: Color
        let isRunning: Bool
        let isLoading: Bool
        let memoryBytes: Int
        let memoryLimitBytes: Int
        let cpuPercent: Double
        let cores: Int
    }

    /// All containers as display rows: running first (colored, sorted by memory), then
    /// stopped (gray). Colors are stable per container across the rings and the list.
    private var rows: [Row] {
        let containers = containerListService.containers
        let samples = statsService.latestSamples

        func isRunning(_ c: Container) -> Bool { c.status.lowercased() == "running" }
        func memory(_ c: Container) -> Int { samples[c.configuration.id]?.memoryBytes ?? 0 }

        // Running containers with a sample, ranked by memory — sets the color order.
        let ranked: [String] = containers
            .filter { isRunning($0) && samples[$0.configuration.id] != nil }
            .sorted { memory($0) > memory($1) }
            .map { $0.configuration.id }

        var colorFor: [String: Color] = [:]
        for (index, id) in ranked.enumerated() {
            colorFor[id] = Self.palette[index % Self.palette.count]
        }

        // All containers: running first, then by memory descending.
        let sorted: [Container] = containers.sorted { a, b in
            if isRunning(a) != isRunning(b) { return isRunning(a) }
            return memory(a) > memory(b)
        }

        return sorted.map { c -> Row in
            let sample = samples[c.configuration.id]
            return Row(
                id: c.configuration.id,
                color: colorFor[c.configuration.id] ?? freeColor,
                isRunning: isRunning(c),
                isLoading: containerListService.loadingContainers.contains(c.configuration.id),
                memoryBytes: sample?.memoryBytes ?? 0,
                memoryLimitBytes: sample?.memoryLimitBytes ?? 0,
                cpuPercent: sample?.cpuPercent ?? 0,
                cores: c.configuration.resources.cpus
            )
        }
    }

    private var runningRows: [Row] { rows.filter(\.isRunning) }

    // MARK: ring data

    private var memoryUsed: Int { runningRows.reduce(0) { $0 + $1.memoryBytes } }
    private var memoryLimit: Int { runningRows.reduce(0) { $0 + $1.memoryLimitBytes } }

    private var memorySegments: [RingSegment] {
        var segments = runningRows.enumerated().map { RingSegment(id: $0.offset, value: Double($0.element.memoryBytes), color: $0.element.color) }
        if memoryLimit > 0 {
            segments.append(RingSegment(id: segments.count, value: Double(max(0, memoryLimit - memoryUsed)), color: freeColor))
        } else if segments.isEmpty {
            segments = [RingSegment(id: 0, value: 1, color: freeColor)]
        }
        return segments
    }

    private var memoryCenter: String {
        memoryLimit > 0 ? "\(Int((Double(memoryUsed) / Double(memoryLimit) * 100).rounded()))%" : "—"
    }

    private var totalCores: Double { runningRows.reduce(0) { $0 + Double($1.cores) } }
    private var busyCores: Double { runningRows.reduce(0) { $0 + $1.cpuPercent / 100 * Double($1.cores) } }

    private var cpuSegments: [RingSegment] {
        var segments = runningRows.enumerated().map { RingSegment(id: $0.offset, value: $0.element.cpuPercent / 100 * Double($0.element.cores), color: $0.element.color) }
        if totalCores > 0 {
            segments.append(RingSegment(id: segments.count, value: max(0, totalCores - busyCores), color: freeColor))
        } else {
            segments = [RingSegment(id: 0, value: 1, color: freeColor)]
        }
        return segments
    }

    private var cpuCenter: String {
        totalCores > 0 ? "\(Int((busyCores / totalCores * 100).rounded()))%" : "0%"
    }

    // MARK: body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card {
                HStack(spacing: 16) {
                    ResourceRing(title: "CPU", center: cpuCenter, segments: cpuSegments)
                    ResourceRing(title: "MEMORY", center: memoryCenter, segments: memorySegments)
                }
                .frame(maxWidth: .infinity)
            }
            // Hovering anywhere in the top card pops out combined system CPU + memory history.
            .contentShape(Rectangle())
            .onHover { hoveringTop = $0 }
            .popover(isPresented: $hoveringTop, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                ResourceHistoryPanel(
                    name: "System",
                    cpuValues: metricHistory(cpu: true),
                    memValues: metricHistory(cpu: false),
                    cpuNow: cpuCenter,
                    memNow: ByteFormat.memory(memoryUsed)
                )
            }

            if !rows.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONTAINERS")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                containerRow(row)
                                if row.id != rows.last?.id { Divider().padding(.vertical, 4) }
                            }
                        }
                    }
                }
            }

            card {
                Button {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Text("Open Orchard").frame(maxWidth: .infinity)
                }
                .font(.callout)
            }

            // Only surface system status when it's stopped — with a way to start it.
            if systemService.systemStatus == .stopped {
                card {
                    HStack(spacing: 8) {
                        Circle().fill(systemService.systemStatus.color).frame(width: 8, height: 8)
                        Text("Containers is stopped").font(.subheadline)
                        Spacer()
                        Button("Start") {
                            Task { @MainActor in await systemService.startSystem() }
                        }
                        .disabled(systemService.isSystemLoading)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .task {
            // Register sampling/refresh synchronously at the start of the task — before any
            // await — so a panel that's closed before these loads finish can't have its
            // `.onDisappear` teardown run first and strand the sampler pinned on. An open
            // panel is its own visibility signal, so history keeps filling while it's shown.
            statsService.beginMenuBarSampling()
            startRefreshTimer()

            await systemService.checkSystemStatus()
			guard await startupSequenceService.prepareForAutomaticRun() else { return }
            await containerListService.loadContainers(showLoading: true)
            await builderService.loadBuilders()
            await dnsService.load(showLoading: true)
            await networkService.load(showLoading: true)
            await systemService.loadSystemDiskUsage(showLoading: false)
			startupSequenceService.runIfEnabled(
				availableContainerIDs: Set(containerListService.containers.map { $0.configuration.id }))
        }
        .onDisappear {
            stopRefreshTimer()
            statsService.endMenuBarSampling()
        }
    }

    // MARK: rows & chrome

    @ViewBuilder
    private func containerRow(_ row: Row) -> some View {
        HStack(spacing: 8) {
            Circle().fill(row.isRunning ? row.color : freeColor).frame(width: 8, height: 8)
            Text(row.id)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)

            if row.isRunning {
                Text(ByteFormat.memory(row.memoryBytes))
                    .font(.caption).fontDesign(.monospaced).foregroundColor(.secondary)
                Text(String(format: "%.0f%%", row.cpuPercent))
                    .font(.caption).fontDesign(.monospaced).foregroundColor(.secondary)
                    .frame(width: 38, alignment: .trailing)
            } else {
                Text("Stopped").font(.caption).foregroundColor(.secondary)
            }

            controlButton(row)
        }
        .contentShape(Rectangle())
        .onHover { if row.isRunning { setContainerHover(row.id, $0) } }
        .popover(isPresented: containerHoverBinding(row.id), arrowEdge: .leading) {
            ResourceHistoryPanel(
                name: row.id,
                cpuValues: containerHistory(id: row.id, cpu: true),
                memValues: containerHistory(id: row.id, cpu: false),
                cpuNow: String(format: "%.1f%%", row.cpuPercent),
                memNow: ByteFormat.memory(row.memoryBytes)
            )
        }
        .contextMenu { rowMenu(row) }
    }

    private func controlButton(_ row: Row) -> some View {
        Group {
            if row.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.5)
            } else {
                Button {
                    Task { @MainActor in
                        if row.isRunning {
                            await containerListService.stopContainer(row.id)
                        } else {
                            await containerListService.startContainer(row.id)
                        }
                    }
                } label: {
                    SwiftUI.Image(systemName: row.isRunning ? "stop.fill" : "play.fill")
                        .imageScale(.small)
                        .foregroundStyle(row.isRunning ? .secondary : Color.green)
                }
                .buttonStyle(.borderless)
                .help(row.isRunning ? "Stop" : "Start")
            }
        }
        // Both states occupy the same fixed box so the row height never changes.
        .frame(width: 22, height: 16)
    }

    @ViewBuilder
    private func rowMenu(_ row: Row) -> some View {
        if row.isRunning {
            Button("Stop") { Task { @MainActor in await containerListService.stopContainer(row.id) } }
        } else {
            Button("Start") { Task { @MainActor in await containerListService.startContainer(row.id) } }
            Button("Remove") { Task { @MainActor in await containerListService.removeContainer(row.id) } }
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func containerHoverBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { hoveredContainer == id }, set: { if !$0 && hoveredContainer == id { hoveredContainer = nil } })
    }

    private func setContainerHover(_ id: String, _ inside: Bool) {
        if inside {
            hoveredContainer = id
        } else if hoveredContainer == id {
            hoveredContainer = nil
        }
    }

    /// Thin a bar series to at most `maxCount` points by even stride, so an hour of samples
    /// stays cheap to draw. Shared by the container and system history panels.
    private func thinned(_ values: [Double], to maxCount: Int = 120) -> [Double] {
        guard values.count > maxCount else { return values }
        let step = Int((Double(values.count) / Double(maxCount)).rounded(.up))
        return values.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
    }

    /// One container's own last-hour history for a metric: CPU% as sampled, memory as a
    /// percentage of its limit. Capped to ~120 bars.
    private func containerHistory(id: String, cpu: Bool) -> [Double] {
        let windowSeconds: TimeInterval = 3600
        let samples = statsService.history.samples(for: StatsKey(id: id))
        guard let newest = samples.last?.timestamp else { return [] }
        let cutoff = newest.addingTimeInterval(-windowSeconds)

        let series = samples.filter { $0.timestamp >= cutoff }.map { cpu ? $0.cpuPercent : $0.memoryPercent }
        return thinned(series)
    }

    /// Recent normalized system history for a metric over the last hour, matching the ring's
    /// meaning: memory is used ÷ total-limit, CPU is busy-cores ÷ total-cores, each as 0…100
    /// per tick. Capped to ~120 bars for the panel.
    private func metricHistory(cpu: Bool) -> [Double] {
        let windowSeconds: TimeInterval = 3600
        let running = containerListService.containers.filter { $0.status.lowercased() == "running" }
        let series = running.map { statsService.history.samples(for: StatsKey(id: $0.configuration.id)) }

        guard let newest = series.compactMap({ $0.last?.timestamp }).max() else { return [] }
        let cutoff = newest.addingTimeInterval(-windowSeconds)
        let windowed = series.map { $0.filter { $0.timestamp >= cutoff } }

        if !cpu {
            // Memory utilisation is summed-usage ÷ summed-limit per tick — exactly what
            // `aggregate` produces via `memoryPercent`, so reuse it rather than re-folding.
            return thinned(aggregate(windowed).map(\.memoryPercent))
        }

        // CPU is core-weighted (busy-cores ÷ total-cores). `aggregate` sums each container's
        // already-normalized cpuPercent and doesn't carry core counts, so it can't express
        // this ratio — fold it here with the per-container weights the ring uses.
        var numerator: [Date: Double] = [:]
        var denominator: [Date: Double] = [:]
        for (container, samples) in zip(running, windowed) {
            let cores = Double(container.configuration.resources.cpus)
            for sample in samples {
                numerator[sample.timestamp, default: 0] += sample.cpuPercent / 100 * cores
                denominator[sample.timestamp, default: 0] += cores
            }
        }
        let values = numerator.keys.sorted().map { time -> Double in
            let denom = denominator[time] ?? 0
            return denom > 0 ? (numerator[time]! / denom * 100) : 0
        }
        return thinned(values)
    }

    private func startRefreshTimer() {
        // Invalidate any existing timer first so a re-entrant `.task` can't strand a duplicate
        // running alongside the new one and double the background polling.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                await systemService.checkSystemStatus()
                await containerListService.loadContainers(showLoading: false)
                await builderService.loadBuilders()
                await dnsService.load(showLoading: false)
                await networkService.load(showLoading: false)
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

/// Pop-out panel beside the menu: CPU and memory history for one container, or for the
/// whole system (when `name` is "System"). Both are last-hour bar charts.
struct ResourceHistoryPanel: View {
    let name: String
    let cpuValues: [Double]
    let memValues: [Double]
    let cpuNow: String
    let memNow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            section("CPU", now: cpuNow, values: cpuValues, color: .blue)
            section("Memory", now: memNow, values: memValues, color: .purple)
        }
        .padding(16)
        .frame(width: 320, height: 220)
    }

    @ViewBuilder
    private func section(_ title: String, now: String, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                Spacer()
                Text(now).font(.caption).fontDesign(.monospaced).foregroundColor(.secondary)
            }
            if values.count >= 2 {
                HistoryBars(values: values, color: color).frame(height: 60)
            } else {
                Text("Collecting…")
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }
}

/// A bar chart drawn with plain SwiftUI paths (no Swift Charts). Auto-scales y to the data.
struct HistoryBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let maxValue = max(values.max() ?? 1, 0.0001)
            let count = values.count
            guard count > 0 else { return }
            let gap: CGFloat = count > 80 ? 0.5 : 1.5
            let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for i in 0..<count {
                let height = size.height * CGFloat(min(1, values[i] / maxValue))
                let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: size.height - height, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(1.5, barWidth / 2)), with: .color(color))
            }
        }
    }
}

/// One arc of a resource ring.
struct RingSegment: Identifiable {
    let id: Int
    let value: Double
    let color: Color
}

/// A segmented donut, drawn with plain SwiftUI shapes (not Swift Charts, which crashes on
/// rapidly-changing data inside a menu-bar window). Each segment is a trimmed arc over a
/// grey track; the total fills the ring, with a centered value and label.
struct ResourceRing: View {
    let title: String
    let center: String
    let segments: [RingSegment]

    private static let lineWidth: CGFloat = 9

    private struct Arc: Identifiable {
        let id: Int
        let from: Double
        let to: Double
        let color: Color
    }

    /// Cumulative 0…1 arc ranges, ignoring non-positive/NaN values.
    private var arcs: [Arc] {
        let values = segments.map { max(0, $0.value.isFinite ? $0.value : 0) }
        let total = values.reduce(0, +)
        guard total > 0 else { return [] }

        var accumulated = 0.0
        var result: [Arc] = []
        for (index, segment) in segments.enumerated() {
            let fraction = values[index] / total
            if fraction > 0 {
                result.append(Arc(id: index, from: accumulated, to: accumulated + fraction, color: segment.color))
            }
            accumulated += fraction
        }
        return result
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(NSColor.tertiaryLabelColor).opacity(0.35), lineWidth: Self.lineWidth)

            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.from, to: max(arc.from, arc.to - 0.012))   // small gap between segments
                    .stroke(arc.color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 0) {
                Text(center)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(title)
                    .font(.system(size: 9))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 84, height: 84)
        .padding(2)
    }
}
