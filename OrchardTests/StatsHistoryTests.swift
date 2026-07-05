import Foundation
import Testing
@testable import Orchard

// Helper: a raw stats read with only the fields a test cares about set.
private func read(
    id: String = "c1",
    cpuUsec: Int = 0,
    mem: Int = 0,
    memLimit: Int = 0,
    blkR: Int = 0,
    blkW: Int = 0,
    rx: Int = 0,
    tx: Int = 0,
    pids: Int = 0
) -> ContainerStats {
    ContainerStats(
        id: id, cpuUsageUsec: cpuUsec,
        memoryUsageBytes: mem, memoryLimitBytes: memLimit,
        blockReadBytes: blkR, blockWriteBytes: blkW,
        networkRxBytes: rx, networkTxBytes: tx, numProcesses: pids
    )
}

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

// MARK: - computeSample

@Test("Normal tick: 1 CPU-second over 1s on 1 core is 100%; byte deltas become per-second rates")
func normalTick() {
    let sample = computeSample(
        prev: read(cpuUsec: 1_000_000, blkR: 0, blkW: 200, rx: 1_000, tx: 500),
        curr: read(cpuUsec: 2_000_000, blkR: 4_000, blkW: 200, rx: 3_000, tx: 1_500),
        at: t0, elapsed: .seconds(1), cpuCount: 1
    )
    #expect(sample.cpuPercent == 100.0)
    #expect(sample.networkRxPerSec == 2_000.0)   // (3000-1000)/1s
    #expect(sample.networkTxPerSec == 1_000.0)
    #expect(sample.blockReadPerSec == 4_000.0)
    #expect(sample.blockWritePerSec == 0.0)      // no change
    #expect(sample.timestamp == t0)
}

@Test("CPU% is normalized to the container's allocated cores")
func cpuNormalizedByCores() {
    // 2 CPU-seconds of work over 1s = 2 busy cores; on a 4-core allocation that's 50%.
    let sample = computeSample(
        prev: read(cpuUsec: 0), curr: read(cpuUsec: 2_000_000),
        at: t0, elapsed: .seconds(1), cpuCount: 4
    )
    #expect(sample.cpuPercent == 50.0)
}

@Test("CPU% clamps to 100 when a container pins more than its allocation")
func cpuClampedTo100() {
    let sample = computeSample(
        prev: read(cpuUsec: 0), curr: read(cpuUsec: 5_000_000),
        at: t0, elapsed: .seconds(1), cpuCount: 1
    )
    #expect(sample.cpuPercent == 100.0)
}

@Test("Counter reset (container restart) clamps negative deltas to zero, not a huge spike")
func counterResetClampsToZero() {
    let sample = computeSample(
        prev: read(cpuUsec: 9_000_000, blkR: 800_000, blkW: 900_000, rx: 1_000_000, tx: 500_000),
        curr: read(cpuUsec: 10_000, blkR: 500, blkW: 100, rx: 2_000, tx: 1_000),
        at: t0, elapsed: .seconds(2), cpuCount: 1
    )
    #expect(sample.cpuPercent == 0.0)
    #expect(sample.networkRxPerSec == 0.0)
    #expect(sample.networkTxPerSec == 0.0)
    #expect(sample.blockReadPerSec == 0.0)
    #expect(sample.blockWritePerSec == 0.0)
}

@Test("Zero elapsed (duplicate read) yields zero rates rather than dividing by zero")
func zeroElapsedGuard() {
    let sample = computeSample(
        prev: read(cpuUsec: 0, rx: 0),
        curr: read(cpuUsec: 1_000_000, rx: 5_000),
        at: t0, elapsed: .zero, cpuCount: 1
    )
    #expect(sample.cpuPercent == 0.0)
    #expect(sample.networkRxPerSec == 0.0)
}

@Test("Negative elapsed (out-of-order / clock oddity) is guarded like zero elapsed")
func negativeElapsedGuard() {
    let sample = computeSample(
        prev: read(cpuUsec: 0, rx: 0),
        curr: read(cpuUsec: 1_000_000, rx: 5_000),
        at: t0, elapsed: .seconds(-1), cpuCount: 1
    )
    #expect(sample.cpuPercent == 0.0)
    #expect(sample.networkRxPerSec == 0.0)
}

@Test("A cpuCount of zero is treated as one core rather than dividing by zero")
func zeroCpuCountTreatedAsOne() {
    let sample = computeSample(
        prev: read(cpuUsec: 0), curr: read(cpuUsec: 1_000_000),
        at: t0, elapsed: .seconds(1), cpuCount: 0
    )
    #expect(sample.cpuPercent == 100.0)
}

@Test("Memory is passed through and memoryPercent is derived from the limit")
func memoryPassthrough() {
    let sample = computeSample(
        prev: read(mem: 0, memLimit: 1_000),
        curr: read(mem: 250, memLimit: 1_000),
        at: t0, elapsed: .seconds(1), cpuCount: 1
    )
    #expect(sample.memoryBytes == 250)
    #expect(sample.memoryLimitBytes == 1_000)
    #expect(sample.memoryPercent == 25.0)
}

@Test("memoryPercent is zero when the limit is zero (unbounded), not a divide-by-zero")
func memoryPercentUnbounded() {
    let sample = computeSample(
        prev: read(mem: 0, memLimit: 0),
        curr: read(mem: 500, memLimit: 0),
        at: t0, elapsed: .seconds(1), cpuCount: 1
    )
    #expect(sample.memoryPercent == 0.0)
}

// MARK: - StatsHistoryStore

private func sample(cpu: Double) -> StatsSample {
    StatsSample(
        timestamp: t0, cpuPercent: cpu, memoryBytes: 0, memoryLimitBytes: 0,
        networkRxPerSec: 0, networkTxPerSec: 0, blockReadPerSec: 0, blockWritePerSec: 0, pids: 0
    )
}

@Test("Store keeps samples in insertion order and reports the latest")
func storeOrderAndLatest() {
    let store = StatsHistoryStore()
    let key = StatsKey(id: "c1")
    store.record(sample(cpu: 1), for: key)
    store.record(sample(cpu: 2), for: key)
    store.record(sample(cpu: 3), for: key)

    #expect(store.samples(for: key).map(\.cpuPercent) == [1, 2, 3])
    #expect(store.latest(for: key)?.cpuPercent == 3)
}

@Test("Store evicts oldest beyond capacity, retaining the most-recent window")
func storeEvictsBeyondCapacity() {
    let store = StatsHistoryStore(capacity: 3)
    let key = StatsKey(id: "c1")
    for i in 1...5 { store.record(sample(cpu: Double(i)), for: key) }

    #expect(store.samples(for: key).map(\.cpuPercent) == [3, 4, 5])
}

@Test("Histories for different keys are isolated")
func storePerKeyIsolation() {
    let store = StatsHistoryStore()
    let a = StatsKey(id: "a")
    let b = StatsKey(id: "b")
    store.record(sample(cpu: 10), for: a)
    store.record(sample(cpu: 20), for: b)

    #expect(store.samples(for: a).map(\.cpuPercent) == [10])
    #expect(store.samples(for: b).map(\.cpuPercent) == [20])
}

@Test("The same id on different hosts is a distinct key (Plan C alignment)")
func storeKeyIncludesHost() {
    let store = StatsHistoryStore()
    let local = StatsKey(host: "local", id: "c1")
    let remote = StatsKey(host: "remote", id: "c1")
    store.record(sample(cpu: 1), for: local)

    #expect(store.samples(for: local).count == 1)
    #expect(store.samples(for: remote).isEmpty)
}

@Test("clear drops one key's history; an unrecorded key is simply empty")
func storeClear() {
    let store = StatsHistoryStore()
    let key = StatsKey(id: "c1")
    store.record(sample(cpu: 1), for: key)
    store.clear(for: key)

    #expect(store.samples(for: key).isEmpty)
    #expect(store.latest(for: StatsKey(id: "never")) == nil)
}

@Test("evictSeries drops a stopped container's series once its newest sample ages past the cutoff, keeping live and recently-stopped ones")
func storeEvictSeries() {
    let store = StatsHistoryStore()
    let stopped = StatsKey(id: "stopped")     // last write long ago
    let recent = StatsKey(id: "recent")       // stopped but still within the window
    let live = StatsKey(id: "live")           // still running

    store.record(sampleAt(-100), for: stopped)
    store.record(sampleAt(3000), for: recent)
    store.record(sampleAt(3500), for: live)

    // "now" is t0+3600 with a 1h retention window → cutoff at t0.
    let cutoff = t0.addingTimeInterval(3600 - 3600)
    store.evictSeries(olderThan: cutoff, keeping: [live])

    #expect(store.samples(for: stopped).isEmpty)   // newest sample is >1h old, not live → evicted
    #expect(store.samples(for: recent).count == 1) // 600s old → still chartable
    #expect(store.samples(for: live).count == 1)   // live key is always kept
}

@Test("mergeRestored splices strictly-older restored samples ahead of live ones without clobbering")
func storeMergeRestored() {
    let store = StatsHistoryStore()
    let key = StatsKey(id: "c1")
    store.record(sampleAt(100, cpu: 5), for: key)   // a live sample recorded before load finished

    // Restored history: one older sample (kept) and one at/after the live one (dropped as dup).
    store.mergeRestored([key: [sampleAt(0, cpu: 1), sampleAt(100, cpu: 99)]])

    #expect(store.samples(for: key).map(\.cpuPercent) == [1, 5])   // older spliced in, live intact

    // A key with no live samples is taken wholesale.
    let fresh = StatsKey(id: "c2")
    store.mergeRestored([fresh: [sampleAt(0, cpu: 7), sampleAt(2, cpu: 8)]])
    #expect(store.samples(for: fresh).map(\.cpuPercent) == [7, 8])
}

// MARK: - Chart point building (windowing + gap segmentation)

private func sampleAt(_ offsetSeconds: Double, cpu: Double = 0) -> StatsSample {
    StatsSample(
        timestamp: t0.addingTimeInterval(offsetSeconds),
        cpuPercent: cpu, memoryBytes: 0, memoryLimitBytes: 0,
        networkRxPerSec: 0, networkTxPerSec: 0, blockReadPerSec: 0, blockWritePerSec: 0, pids: 0
    )
}

@Test("buildPoints splits the line into segments across a sampling gap, stamping seconds-ago")
func chartPointsSegmentAcrossGap() {
    // Three 2s ticks, a 30s pause (view hidden), then two more ticks.
    let samples = [0, 2, 4, 34, 36].map { sampleAt(Double($0)) }
    // Anchor "now" at the newest sample: this asserts the segmentation/positioning logic
    // independent of stale-gap handling (covered separately below).
    let points = chartPoints(from: samples, now: samples.last!.timestamp, windowSeconds: 300, gapThreshold: 5)

    #expect(points.map(\.segment) == [0, 0, 0, 1, 1])   // line breaks at the gap
    #expect(points.first?.secondsAgo == -36)            // oldest, relative to now
    #expect(points.last?.secondsAgo == 0)               // newest lands exactly at "now"
}

@Test("buildPoints drops samples older than the visible window")
func chartPointsWindowing() {
    // "now" at 400s; window 300s keeps only samples within 300s of it.
    let samples = [0, 100, 400].map { sampleAt(Double($0)) }
    let points = chartPoints(from: samples, now: t0.addingTimeInterval(400), windowSeconds: 300, gapThreshold: 5)

    #expect(points.count == 2)                          // the 0s sample (400s old) is dropped
    #expect(points.first?.secondsAgo == -300)
}

@Test("Stale data anchors to wall-clock now: the newest sample sits back from the now edge, and data older than the window falls off")
func chartPointsAnchoredToWallClock() {
    // Samples stop at t0+40; the view renders 100s later (container stopped / app resumed).
    let samples = [0, 20, 40].map { sampleAt(Double($0)) }
    let now = t0.addingTimeInterval(140)
    let points = chartPoints(from: samples, now: now, windowSeconds: 120, gapThreshold: 5)

    // The 0s sample is 140s old → outside the 120s window → dropped.
    #expect(points.count == 2)
    // The newest sample is 100s old, so it draws at -100 (a gap to the right), not at 0.
    #expect(points.last?.secondsAgo == -100)
    #expect(points.allSatisfy { $0.secondsAgo < 0 })   // nothing masquerades as "now"
}

// MARK: - Downsampling

@Test("downsample buckets a long series to the target and keeps the newest sample at the end")
func downsampleReducesToTarget() {
    let samples = (0..<100).map { sampleAt(Double($0)) }
    let reduced = downsample(samples, to: 10)

    #expect(reduced.count == 10)
    #expect(reduced.last?.timestamp == samples.last?.timestamp)   // newest preserved → still "now"
}

@Test("downsample averages metric values within each bucket")
func downsampleAverages() {
    let reduced = downsample([sampleAt(0, cpu: 0), sampleAt(1, cpu: 100)], to: 1)

    #expect(reduced.count == 1)
    #expect(reduced.first?.cpuPercent == 50)
}

@Test("downsample leaves a series that already fits unchanged")
func downsampleNoop() {
    let samples = [0, 2, 4].map { sampleAt(Double($0)) }
    #expect(downsample(samples, to: 400) == samples)
}

// MARK: - Store retention

@Test("Store prunes samples older than its retention window")
func storeRetention() {
    let store = StatsHistoryStore(retention: 60)   // 60s window
    let key = StatsKey(id: "c1")
    store.record(sampleAt(0), for: key)            // t0
    store.record(sampleAt(120), for: key)          // t0+120 → t0 is now 120s old > 60s

    #expect(store.samples(for: key).count == 1)    // the t0 sample aged out
}

// MARK: - Persistence

@Test("Persistence round-trips history and drops samples older than the retention window on load")
func persistenceRoundTrips() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = StatsPersistence(fileURL: url)
    let old = sampleAt(-100_000, cpu: 1)   // ~27h before t0
    let recent = sampleAt(-10, cpu: 2)
    try store.save([StatsKey(id: "c1"): [old, recent]])

    let loaded = store.load(retention: 86_400, now: t0)
    #expect(loaded[StatsKey(id: "c1")]?.map(\.cpuPercent) == [2])   // old pruned, recent kept
}

@Test("Persistence returns empty rather than throwing when the file is missing")
func persistenceMissingFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
    #expect(StatsPersistence(fileURL: url).load().isEmpty)
}

@Test("Persistence drops history whose on-disk schema version this build doesn't understand")
func persistenceVersionMismatch() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    // A future-versioned file with an otherwise-valid series must be dropped, not decoded.
    let future = #"{"version":9999,"series":[{"host":"local","id":"c1","samples":[]}]}"#
    try future.data(using: .utf8)!.write(to: url)

    #expect(StatsPersistence(fileURL: url).load().isEmpty)
}

// MARK: - Aggregation

private func aggSample(at offset: Double, cpu: Double, mem: Int, memLimit: Int, rx: Double) -> StatsSample {
    StatsSample(
        timestamp: t0.addingTimeInterval(offset),
        cpuPercent: cpu, memoryBytes: mem, memoryLimitBytes: memLimit,
        networkRxPerSec: rx, networkTxPerSec: 0, blockReadPerSec: 0, blockWritePerSec: 0, pids: 0
    )
}

@Test("aggregate sums same-timestamp samples across containers into one system series")
func aggregateSumsAcrossContainers() {
    let a = [aggSample(at: 0, cpu: 10, mem: 100, memLimit: 500, rx: 1),
             aggSample(at: 2, cpu: 20, mem: 200, memLimit: 500, rx: 2)]
    let b = [aggSample(at: 0, cpu: 30, mem: 50, memLimit: 250, rx: 3),
             aggSample(at: 2, cpu: 40, mem: 60, memLimit: 250, rx: 4)]

    let result = aggregate([a, b])

    #expect(result.map(\.cpuPercent) == [40, 60])            // 10+30, 20+40 (can exceed 100)
    #expect(result.map(\.memoryBytes) == [150, 260])         // summed usage
    #expect(result.map(\.memoryLimitBytes) == [750, 750])    // summed limits
    #expect(result.map(\.networkRxPerSec) == [4, 6])
}

@Test("aggregate keeps a lone container's samples and stays chronological")
func aggregateSingleContainer() {
    let a = [aggSample(at: 2, cpu: 5, mem: 0, memLimit: 0, rx: 0),
             aggSample(at: 0, cpu: 9, mem: 0, memLimit: 0, rx: 0)]   // out of order

    let result = aggregate([a])

    #expect(result.map(\.cpuPercent) == [9, 5])   // sorted by timestamp ascending
}
