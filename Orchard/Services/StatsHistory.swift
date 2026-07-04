import Foundation

/// A derived, per-tick resource sample for one container. Unlike `ContainerStats`
/// (raw cumulative counters), every field here is an instantaneous value or a rate,
/// ready to plot directly. Produced by `computeSample` from two consecutive raw reads.
///
/// The timestamp is **wall-clock** (`Date`) so samples are meaningful across app launches
/// and can be persisted. Rate math never uses it — `computeSample` takes a separate
/// monotonic `elapsed` so clock adjustments can't distort rates.
struct StatsSample: Codable, Equatable {
    let timestamp: Date
    /// CPU use as a percentage of the container's allocated cores, clamped 0…100.
    let cpuPercent: Double
    let memoryBytes: Int
    let memoryLimitBytes: Int
    let networkRxPerSec: Double
    let networkTxPerSec: Double
    let blockReadPerSec: Double
    let blockWritePerSec: Double
    let pids: Int

    var memoryPercent: Double {
        guard memoryLimitBytes > 0 else { return 0 }
        return Double(memoryBytes) / Double(memoryLimitBytes) * 100.0
    }
}

/// Identity for a container's history: `(host, id)` from day one so multi-host work
/// (Plan C) inherits the store unchanged. Today `host` is always the local daemon.
struct StatsKey: Hashable, Codable {
    let host: String
    let id: String

    static let localHost = "local"

    init(host: String = StatsKey.localHost, id: String) {
        self.host = host
        self.id = id
    }
}

/// Pure: turn two consecutive raw reads into one plottable sample. The testable heart
/// of the sampling layer — no clock, no state, no I/O.
///
/// - `at` stamps the sample's wall-clock timestamp only; all rate math uses `elapsed`.
/// - `elapsed` is the monotonic gap between the two reads.
/// - `cpuCount` is the container's allocated cores — the CPU% denominator.
///
/// Rules: a non-positive `elapsed` (a repeated/zero-gap read) yields zero rates rather
/// than dividing by zero; a negative counter delta (a container restart resets its
/// cumulative counters) clamps to zero rather than drawing a huge negative spike;
/// CPU% is normalized to the allocation and clamped to 0…100.
func computeSample(
    prev: ContainerStats,
    curr: ContainerStats,
    at: Date,
    elapsed: Duration,
    cpuCount: Int
) -> StatsSample {
    let seconds = elapsed.inSeconds
    let cores = Double(max(1, cpuCount))

    func perSecond(_ previous: Int, _ current: Int) -> Double {
        guard seconds > 0 else { return 0 }
        let delta = current - previous
        guard delta > 0 else { return 0 }   // counter reset or no progress
        return Double(delta) / seconds
    }

    let cpuPercent: Double = {
        guard seconds > 0 else { return 0 }
        let deltaUsec = curr.cpuUsageUsec - prev.cpuUsageUsec
        guard deltaUsec > 0 else { return 0 }
        // Δ CPU-seconds over Δ wall-seconds = cores busy; normalize to allocated cores.
        let coresBusy = (Double(deltaUsec) / 1_000_000.0) / seconds
        let pct = coresBusy / cores * 100.0
        return min(100.0, max(0.0, pct))
    }()

    return StatsSample(
        timestamp: at,
        cpuPercent: cpuPercent,
        memoryBytes: curr.memoryUsageBytes,
        memoryLimitBytes: curr.memoryLimitBytes,
        networkRxPerSec: perSecond(prev.networkRxBytes, curr.networkRxBytes),
        networkTxPerSec: perSecond(prev.networkTxBytes, curr.networkTxBytes),
        blockReadPerSec: perSecond(prev.blockReadBytes, curr.blockReadBytes),
        blockWritePerSec: perSecond(prev.blockWriteBytes, curr.blockWriteBytes),
        pids: curr.numProcesses
    )
}

/// Pure: fold many per-container series into one system-wide series by summing every
/// field of samples that share a timestamp. All running containers are sampled together
/// (one wall-clock stamp per tick), so their samples align exactly. `cpuPercent` becomes
/// total load across containers (can exceed 100), memory becomes total used vs total
/// limit, and rates/pids sum. Result is chronological.
func aggregate(_ histories: [[StatsSample]]) -> [StatsSample] {
    var byTime: [Date: StatsSample] = [:]
    for series in histories {
        for sample in series {
            guard let running = byTime[sample.timestamp] else {
                byTime[sample.timestamp] = sample
                continue
            }
            byTime[sample.timestamp] = StatsSample(
                timestamp: sample.timestamp,
                cpuPercent: running.cpuPercent + sample.cpuPercent,
                memoryBytes: running.memoryBytes + sample.memoryBytes,
                memoryLimitBytes: running.memoryLimitBytes + sample.memoryLimitBytes,
                networkRxPerSec: running.networkRxPerSec + sample.networkRxPerSec,
                networkTxPerSec: running.networkTxPerSec + sample.networkTxPerSec,
                blockReadPerSec: running.blockReadPerSec + sample.blockReadPerSec,
                blockWritePerSec: running.blockWritePerSec + sample.blockWritePerSec,
                pids: running.pids + sample.pids
            )
        }
    }
    return byTime.values.sorted { $0.timestamp < $1.timestamp }
}

/// Bounded per-container sample history. Each key keeps samples within a rolling
/// `retention` window (default 24h) plus a hard count cap as a runaway backstop.
final class StatsHistoryStore {
    let capacity: Int
    let retention: TimeInterval
    private var buffers: [StatsKey: [StatsSample]] = [:]

    init(capacity: Int = 50_000, retention: TimeInterval = 86_400) {
        self.capacity = max(1, capacity)
        self.retention = retention
    }

    func record(_ sample: StatsSample, for key: StatsKey) {
        var buffer = buffers[key] ?? []
        buffer.append(sample)
        // Prune anything older than the retention window relative to the newest sample.
        let cutoff = sample.timestamp.addingTimeInterval(-retention)
        buffer.removeAll { $0.timestamp < cutoff }
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        buffers[key] = buffer
    }

    /// Chronological samples for one container (oldest first). Empty if none recorded.
    func samples(for key: StatsKey) -> [StatsSample] {
        buffers[key] ?? []
    }

    func latest(for key: StatsKey) -> StatsSample? {
        buffers[key]?.last
    }

    /// Every series, for cross-container aggregation (system dashboard).
    func allSamples() -> [[StatsSample]] {
        Array(buffers.values)
    }

    /// A copy of the whole store, for persistence.
    func snapshot() -> [StatsKey: [StatsSample]] {
        buffers
    }

    /// Replace all in-memory history — used to seed from disk on launch.
    func replaceAll(_ snapshot: [StatsKey: [StatsSample]]) {
        buffers = snapshot
    }

    func clear(for key: StatsKey) {
        buffers[key] = nil
    }

    func removeAll() {
        buffers.removeAll()
    }
}

extension Duration {
    /// Seconds as a Double. `components` splits into whole seconds + attoseconds.
    var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
