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
    /// Latest raw stats per **machine id** (re-keyed off the backing container). Container
    /// machines are sampled through their backing container but tracked under the stable
    /// machine id so history survives the backing id changing across reboots.
    @Published var machineStats: [ContainerStats] = []

    /// Supplies the running machines to sample each tick: `(machineId, backingContainerId,
    /// cpus)`. Wired from `MachineService` in `AppServices`; empty until then.
    var machineStatTargets: @MainActor () -> [(machineId: String, backingId: String, cpus: Int)] = { [] }

    /// The internal sampling key for a machine — namespaced so it never collides with a
    /// container id in the shared history/sample maps. `nonisolated` so the concurrent
    /// sampling task group can build it off the main actor.
    nonisolated static func machineStatKey(_ machineId: String) -> String { "machine::\(machineId)" }

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
    ///
    /// NOTE (Plan C): this and `latestSamples` key on the **bare container id**, while the
    /// history store keys on `StatsKey(host, id)`. Today `host` is always local so they align,
    /// but multi-host must re-key these to `(host, id)` too — otherwise two hosts' same-id
    /// containers would share one rate baseline here and delta across each other.
    private var previousRaw: [String: (stats: ContainerStats, at: ContinuousClock.Instant)] = [:]
    private var samplingTimer: Timer?
    private var currentInterval: TimeInterval = 0
    /// Ref-count of on-screen stats consumers in a main-window view (Dashboard, container
    /// overview). Subject to occlusion — a minimized window's `onAppear`-registered consumer
    /// isn't really watching, so these only drive sampling while the window is visible.
    private var samplingConsumers = 0
    /// Whether the menu-bar panel is open. Its own visibility signal: the status item doesn't
    /// contribute to `NSApplication.occlusionState`, so an open panel keeps sampling alive on
    /// its own even when the main window is hidden.
    private var menuBarOpen = false
    /// Set by `activate()` — until then, sampling only runs while a consumer is on screen.
    private var backgroundSamplingEnabled = false
    /// Whether any app window is on screen. Background sampling pauses while fully hidden
    /// or minimized.
    private var appVisible = true

    /// Whether the app has a surface actually presenting stats: a visible main window or the
    /// open menu-bar panel. Sampling pauses entirely when neither is true.
    private var effectivelyVisible: Bool { appVisible || menuBarOpen }
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

        // Start sampling immediately — don't block the first frame on disk I/O.
        reconfigureSampler()

        // Load persisted history off the main actor, then merge it into whatever the live
        // sampler has already recorded. `latestSamples` is deliberately NOT seeded: restored
        // samples can be up to 24h old and must never render as a live "current" reading —
        // the table/rings stay in their "--"/"Collecting…" state until the first fresh tick.
        let persistence = self.persistence
        Task { [weak self] in
            let restored = await Task.detached { persistence.load() }.value
            self?.history.mergeRestored(restored)
        }

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

    /// Call when the menu-bar panel opens — its own visibility signal (the status item isn't
    /// in `occlusionState`), so an open panel samples at the fast cadence regardless of the
    /// main window. Idempotent so an out-of-order open/close pair can't strand the state.
    func beginMenuBarSampling() {
        guard !menuBarOpen else { return }
        menuBarOpen = true
        reconfigureSampler()
    }

    /// Call when the menu-bar panel closes.
    func endMenuBarSampling() {
        guard menuBarOpen else { return }
        menuBarOpen = false
        reconfigureSampler()
    }

    /// Pick the cadence for the current state and (re)schedule the timer only if it changed.
    /// Visibility gates everything: a hidden app (no visible window, no open menu-bar panel)
    /// pauses even if a stats view is still `onAppear`-registered, because SwiftUI doesn't
    /// fire `onDisappear` on minimize so `samplingConsumers` alone can't tell watched from hidden.
    private func reconfigureSampler() {
        let desired: TimeInterval?
        if !effectivelyVisible {
            desired = nil                            // nothing on screen → pause
        } else if samplingConsumers > 0 || menuBarOpen {
            desired = Self.samplingInterval          // a visible consumer is actively looking
        } else if backgroundSamplingEnabled {
            desired = Self.idleInterval              // background only while a window is on screen
        } else {
            desired = nil                            // not activated and nobody looking → pause
        }

        guard desired != currentInterval else { return }
        currentInterval = desired ?? 0
        samplingTimer?.invalidate()
        samplingTimer = nil

        guard let interval = desired else { return }
        // Add to the run loop in `.common` mode rather than `Timer.scheduledTimer` (which uses
        // `.default`): otherwise sampling — and the live charts — pause during scroll/menu tracking.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        samplingTimer = timer
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
        // Allocated cores per container/machine — the CPU% denominator for computeSample.
        var cpuCounts = Dictionary(running.map { ($0.configuration.id, $0.configuration.resources.cpus) },
                                   uniquingKeysWith: { first, _ in first })
        // Running machines are sampled through their backing container, but re-keyed onto the
        // stable machine id so a reboot (which changes the backing id) doesn't fork history.
        let machineTargets = machineStatTargets()
        for target in machineTargets {
            cpuCounts[Self.machineStatKey(target.machineId)] = target.cpus
        }
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

        // Machine stats, re-keyed from backing container id → machine sampling key.
        let machineResults: [ContainerStats] = await withTaskGroup(of: ContainerStats?.self) { group in
            for target in machineTargets {
                group.addTask {
                    guard let stats = try? await backend.stats(id: target.backingId) else { return nil }
                    return stats.with(id: Self.machineStatKey(target.machineId))
                }
            }
            var collected: [ContainerStats] = []
            for await case let stats? in group {
                collected.append(stats)
            }
            return collected
        }

        recordSamples(results + machineResults, cpuCounts: cpuCounts)

        containerStats = results
        // Expose machine stats under the bare machine id for the machine UI to look up.
        machineStats = machineResults.map { $0.with(id: String($0.id.dropFirst("machine::".count))) }
        isStatsLoading = false
        // Alert only when every running container failed (results empty) AND the load was
        // user-initiated — the background poll stays silent; DashboardView shows a passive panel.
        if showLoading && !runningIds.isEmpty && results.isEmpty {
            alertCenter.error("Unable to read container stats. Check that the container service is running.")
        }
    }

    /// Whether the stats page should show its passive "unavailable" panel: there are
    /// running containers but no stats came back. Drives non-modal UI in DashboardView.
    var statsUnavailable: Bool {
        !containerList.containers.filter { $0.status == "running" }.isEmpty && containerStats.isEmpty
    }

    // MARK: - Machine stats accessors (keyed by stable machine id)

    /// Latest derived sample for a machine, or nil until it has two raw reads.
    func machineSample(_ machineId: String) -> StatsSample? {
        latestSamples[Self.machineStatKey(machineId)]
    }

    /// Latest raw stats for a machine (absolute memory/net/disk values).
    func machineRawStats(_ machineId: String) -> ContainerStats? {
        machineStats.first { $0.id == machineId }
    }

    /// Chronological sample history for a machine (drives its charts/sparklines).
    func machineHistory(_ machineId: String) -> [StatsSample] {
        history.samples(for: StatsKey(id: Self.machineStatKey(machineId)))
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

        // Evict whole series for containers that have been gone longer than the retention
        // window. Their buffers never get a fresh write, so per-write time-pruning never
        // touches them — without this they'd persist (and re-serialize) in memory forever.
        // Recently-stopped containers stay until their newest sample ages out, so they can
        // still be charted.
        let liveKeys = Set(reads.map { StatsKey(id: $0.id) })
        history.evictSeries(olderThan: wallNow.addingTimeInterval(-history.retention), keeping: liveKeys)
    }
}
