import AppKit
import Foundation

/// Owns per-container resource stats. Reads the running containers from the container
/// list (owned by `ContainerListService`), fetches stats for each, derives plottable
/// samples, accumulates history, and persists it across launches.
@MainActor
final class StatsService: ObservableObject {
    @Published var containerStats: [ContainerStats] = []
    @Published var isStatsLoading = false
    /// Latest derived sample per container id — drives the table's real CPU% and the
    /// current-value cards. Empty for a container until it has two raw reads.
    @Published var latestSamples: [String: StatsSample] = [:]

    /// Accumulated time-series history, keyed `(host, id)`. Survives view switches and
    /// (via `persistence`) app relaunches. Read by charts.
    let history = StatsHistoryStore()

    private let backend: ContainerBackend
    private let alertCenter: AlertCenter
    private let containerList: ContainerListService
    private let persistence: StatsPersistence

    init(
        backend: ContainerBackend,
        alertCenter: AlertCenter,
        containerList: ContainerListService,
        persistence: StatsPersistence = StatsPersistence()
    ) {
        self.backend = backend
        self.alertCenter = alertCenter
        self.containerList = containerList
        self.persistence = persistence
    }

    private var isRefreshing = false

    // MARK: - Sampling

    private let clock = ContinuousClock()
    /// Previous raw read per container id, with the *monotonic* instant it was taken — the
    /// other half of each `computeSample` call. Monotonic so rates ignore clock changes.
    private var previousRaw: [String: (stats: ContainerStats, at: ContinuousClock.Instant)] = [:]
    private var samplingTimer: Timer?
    private var currentInterval: TimeInterval = 0
    /// Ref-count of on-screen stats consumers (container overview). While ≥1 we sample at
    /// the fast cadence; otherwise the slow background cadence (once activated).
    private var samplingConsumers = 0
    /// Set by `activate()` — until then, sampling only runs while a consumer is on screen.
    private var backgroundSamplingEnabled = false
    /// Whether any app window is on screen. Background sampling pauses while fully hidden
    /// or minimized; an explicit on-screen consumer still samples regardless.
    private var appVisible = true
    private var ticksSinceSave = 0

    /// Fast cadence while a stats view is visible — smooth charts.
    static let samplingInterval: TimeInterval = 2.0
    /// Slow always-on cadence when nothing is on screen — keeps 1h/24h history filling
    /// without hammering XPC for charts nobody is watching.
    static let idleInterval: TimeInterval = 10.0

    /// Start always-on background sampling and restore persisted history. Called once at
    /// app launch (not from `init`, so unit tests that build the service stay side-effect
    /// free). Idempotent.
    func activate() {
        guard !backgroundSamplingEnabled else { return }
        backgroundSamplingEnabled = true

        let restored = persistence.load()
        history.replaceAll(restored)
        for (key, samples) in restored where key.host == StatsKey.localHost {
            if let last = samples.last { latestSamples[key.id] = last }
        }

        reconfigureSampler()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistNow(inBackground: false) }
        }

        // Pause/resume background sampling as the app is hidden/shown.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.appVisible = NSApplication.shared.occlusionState.contains(.visible)
                self.reconfigureSampler()
            }
        }
    }

    /// Call when a stats-consuming view appears — bumps sampling to the fast cadence.
    func beginSampling() {
        samplingConsumers += 1
        reconfigureSampler()
    }

    /// Call when a stats-consuming view disappears — drops back to the background cadence
    /// (or stops entirely if background sampling isn't active). History is retained.
    func endSampling() {
        samplingConsumers = max(0, samplingConsumers - 1)
        reconfigureSampler()
    }

    /// Pick the cadence for the current state and (re)schedule the timer only if it changed.
    private func reconfigureSampler() {
        let desired: TimeInterval?
        if samplingConsumers > 0 {
            desired = Self.samplingInterval          // someone's actively looking → always sample
        } else if backgroundSamplingEnabled && appVisible {
            desired = Self.idleInterval              // background only while a window is on screen
        } else {
            desired = nil                            // hidden and nobody looking → pause
        }

        guard desired != currentInterval else { return }
        currentInterval = desired ?? 0
        samplingTimer?.invalidate()
        samplingTimer = nil

        guard let interval = desired else { return }
        samplingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    private func tick() async {
        await load(showLoading: false)
        guard backgroundSamplingEnabled else { return }
        // Persist roughly once a minute; a clean quit also saves via willTerminate.
        ticksSinceSave += 1
        let savesEvery = max(1, Int((60.0 / max(currentInterval, 1)).rounded()))
        if ticksSinceSave >= savesEvery {
            ticksSinceSave = 0
            persistNow(inBackground: true)
        }
    }

    private func persistNow(inBackground: Bool) {
        let snapshot = history.snapshot()
        let store = persistence
        if inBackground {
            Task.detached { try? store.save(snapshot) }
        } else {
            try? store.save(snapshot)
        }
    }

    func load(showLoading: Bool = true) async {
        // Overlapping loads must not pile up if one runs slow.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if showLoading {
            isStatsLoading = true
            alertCenter.dismiss()
        }

        let running = containerList.containers.filter { $0.status == "running" }
        let runningIds = running.map { $0.configuration.id }
        // Allocated cores per container — the CPU% denominator for computeSample.
        let cpuCounts = Dictionary(running.map { ($0.configuration.id, $0.configuration.resources.cpus) },
                                   uniquingKeysWith: { first, _ in first })
        let backend = self.backend

        // Fetch every container's stats concurrently rather than serially.
        let results: [ContainerStats] = await withTaskGroup(of: ContainerStats?.self) { group in
            for id in runningIds {
                group.addTask { try? await backend.stats(id: id) }
            }
            var collected: [ContainerStats] = []
            for await case let stats? in group {
                collected.append(stats)
            }
            return collected
        }

        recordSamples(results, cpuCounts: cpuCounts)

        containerStats = results
        isStatsLoading = false
        // Alert only when every running container failed (results empty) AND the load was
        // user-initiated — the background poll stays silent; StatsView shows a passive panel.
        if showLoading && !runningIds.isEmpty && results.isEmpty {
            alertCenter.error("Unable to read container stats. Check that the container service is running.")
        }
    }

    /// Whether the stats page should show its passive "unavailable" panel: there are
    /// running containers but no stats came back. Drives non-modal UI in StatsView.
    var statsUnavailable: Bool {
        !containerList.containers.filter { $0.status == "running" }.isEmpty && containerStats.isEmpty
    }

    /// Derive a sample from each raw read against its predecessor, append to history, and
    /// republish the latest per container. Containers with no prior read only seed the
    /// baseline (need two points for a rate). Stopped/vanished containers are pruned from
    /// the live maps (history is retained) so a restart deltas fresh, not across the gap.
    private func recordSamples(_ reads: [ContainerStats], cpuCounts: [String: Int]) {
        let monotonicNow = clock.now      // rate math
        let wallNow = Date()              // sample stamp (persistable, cross-launch)
        var samples = latestSamples

        for read in reads {
            defer { previousRaw[read.id] = (read, monotonicNow) }
            guard let prev = previousRaw[read.id] else { continue }
            let sample = computeSample(
                prev: prev.stats,
                curr: read,
                at: wallNow,
                elapsed: prev.at.duration(to: monotonicNow),
                cpuCount: cpuCounts[read.id] ?? 1
            )
            history.record(sample, for: StatsKey(id: read.id))
            samples[read.id] = sample
        }

        let live = Set(reads.map(\.id))
        previousRaw = previousRaw.filter { live.contains($0.key) }
        samples = samples.filter { live.contains($0.key) }
        latestSamples = samples
    }
}
