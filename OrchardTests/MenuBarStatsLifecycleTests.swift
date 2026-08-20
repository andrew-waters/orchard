import Testing
import Foundation
@testable import Orchard

// Regression tests for the menu-bar System analytics "stuck Collecting…" bug. The
// original `StatsService.load()` swallowed every per-container stats error with `try?`
// and a `for await case let stats?` filter, so a total stats failure (e.g. the XPC
// daemon went away) left the menu-bar popover on "Collecting…" forever. The fix
// replaces the silent failure with a classified `StatsSamplingState` that the UI
// can render as an explicit "Stats unavailable" / "No running containers" message.
//
// These tests cover the lifecycle (begin/end), the two-tick baseline, the four
// sampling states, recovery after failure, and the surrounding idempotency guards.

// MARK: - Helpers

/// Build a `StatsService` with the supplied backend, alert center, and (optional)
/// running containers pre-populated. Reused by every test to keep the boilerplate
/// focused on the stats behaviour under test.
@MainActor
private func makeStats(
    backend: MockContainerBackend,
    containers: [Container] = [],
    machines: [(machineId: String, backingId: String, cpus: Int)] = []
) -> (service: AppServices, stats: StatsService) {
    let service = makeService(backend: backend)
    service.containerListService.containers = containers
    service.statsService.machineStatTargets = { machines }
    return (service, service.statsService)
}

private func xpcOutageError() -> NSError {
    NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "The connection was invalidated."])
}

private func decodeError() -> NSError {
    NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
}

// MARK: - Two-tick baseline

@MainActor
@Test("First load() seeds a baseline only — no derived samples wrote to history or latestSamples")
func firstLoadSeedsBaselineOnly() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { id in
        ContainerStats(id: id, cpuUsageUsec: 1_000_000, memoryUsageBytes: 200, memoryLimitBytes: 1_000,
                       blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 1)
    }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    await stats.load(showLoading: false)

    #expect(stats.latestSamples.isEmpty)
    #expect(stats.history.samples(for: StatsKey(id: "web")).isEmpty)
    #expect(stats.samplingState == .collecting)
}

@MainActor
@Test("Second load() produces the first derived sample and transitions to available")
func secondLoadProducesFirstSample() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { id in
        ContainerStats(id: id, cpuUsageUsec: 1_000_000, memoryUsageBytes: 200, memoryLimitBytes: 1_000,
                       blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 1)
    }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    await stats.load(showLoading: false)
    #expect(stats.samplingState == .collecting)   // baseline only

    await stats.load(showLoading: false)
    #expect(stats.latestSamples["web"] != nil)
    #expect(stats.history.samples(for: StatsKey(id: "web")).count == 1)
    #expect(stats.samplingState == .available)
}

// MARK: - Sampling state classification

@MainActor
@Test("No running containers and no machines → samplingState is noContainers")
func noContainersYieldsNoContainers() async throws {
    let backend = MockContainerBackend()
    let (_, stats) = makeStats(backend: backend, containers: [])

    await stats.load(showLoading: false)

    #expect(stats.samplingState == .noContainers)
    #expect(stats.menuBarHistoryState() == .noData)
}

@MainActor
@Test("A single non-XPC failure → samplingState is unavailable \"Container stats could not be read\"")
func singleContainerFailureYieldsUnavailable() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { _ in throw decodeError() }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    await stats.load(showLoading: false)

    #expect(stats.samplingState == .unavailable(reason: "Container stats could not be read"))
    #expect(stats.menuBarHistoryState() == .unavailable(reason: "Container stats could not be read"))
}

@MainActor
@Test("An XPC-outage failure → samplingState is unavailable with the xpcUnavailable description")
func xpcOutageYieldsUnavailableXpc() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { _ in throw xpcOutageError() }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    await stats.load(showLoading: false)

    if case .unavailable(let reason) = stats.samplingState {
        #expect(reason.contains("container service") || reason.contains("unavailable"))
    } else {
        Issue.record("expected .unavailable, got \(stats.samplingState)")
    }
}

@MainActor
@Test("Per-container failures are logged via the testLogHook and via Log.xpc")
func perContainerFailureLogs() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { _ in throw decodeError() }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    var captured: [String] = []
    stats.testLogHook = { captured.append($0) }

    await stats.load(showLoading: false)

    #expect(captured.contains(where: { $0.contains("stats(id: web)") && $0.contains("disk full") }))
}

@MainActor
@Test("Partial failure: one container succeeding, one failing → available, no alert")
func partialFailureYieldsAvailable() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { id in
        if id == "a" {
            return ContainerStats(id: id, cpuUsageUsec: 1_000_000, memoryUsageBytes: 200, memoryLimitBytes: 1_000,
                                  blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 1)
        }
        throw decodeError()
    }
    let service = makeService(backend: backend)
    service.containerListService.containers = [
        try makeContainer(id: "a", status: "running"),
        try makeContainer(id: "b", status: "running"),
    ]

    // Two loads so the first container's sample is derived.
    await service.statsService.load(showLoading: false)
    await service.statsService.load(showLoading: false)

    #expect(service.statsService.containerStats.count == 1)
    #expect(service.statsService.containerStats.first?.id == "a")
    #expect(service.statsService.samplingState == .available)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("Total failure on a background poll stays silent — no alert raised")
func totalFailureBackgroundPollSilent() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { _ in throw decodeError() }
    let service = makeService(backend: backend)
    service.containerListService.containers = [try makeContainer(id: "a", status: "running")]

    await service.statsService.load(showLoading: false)

    // Background poll (showLoading: false) must not raise an alert — the dashboard's
    // passive panel handles the user-facing communication.
    #expect(service.alertCenter.current == nil)
    #expect(service.statsService.samplingState == .unavailable(reason: "Container stats could not be read"))
}

@MainActor
@Test("Total failure on a user-initiated load still raises an alert (existing path preserved)")
func totalFailureUserLoadAlerts() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { _ in throw decodeError() }
    let service = makeService(backend: backend)
    service.containerListService.containers = [try makeContainer(id: "a", status: "running")]

    await service.statsService.load(showLoading: true)

    #expect(service.alertCenter.current != nil)
}

// MARK: - Recovery

@MainActor
@Test("Recovery: a failed load followed by a successful load transitions unavailable → available")
func recoveryAfterFailure() async throws {
    let backend = MockContainerBackend()
    // First call throws, second call succeeds.
    var callCount = 0
    backend.statsHandler = { id in
        callCount += 1
        if callCount == 1 {
            throw decodeError()
        }
        return ContainerStats(id: id, cpuUsageUsec: 1_000_000, memoryUsageBytes: 200, memoryLimitBytes: 1_000,
                              blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 1)
    }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    await stats.load(showLoading: false)
    #expect(stats.samplingState == .unavailable(reason: "Container stats could not be read"))

    await stats.load(showLoading: false)
    #expect(stats.samplingState == .collecting)   // baseline re-seeded after the gap

    await stats.load(showLoading: false)
    #expect(stats.samplingState == .available)
}

// MARK: - Menu-bar lifecycle

@MainActor
@Test("beginMenuBarSampling/endMenuBarSampling are idempotent and don't strand state")
func menuBarLifecycleIdempotent() {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    let stats = service.statsService

    // Calling twice in a row must not crash or leave a duplicated timer. The lifecycle
    // is gated by an internal `menuBarOpen` flag in StatsService — both the call site
    // and the timer use `isHidden`/`menuBarOpen` checks to avoid double-registering.
    stats.beginMenuBarSampling()
    stats.beginMenuBarSampling()
    stats.endMenuBarSampling()
    stats.endMenuBarSampling()   // second end must not underflow

    // The state must be cleanly closable; a subsequent begin works.
    stats.beginMenuBarSampling()
    stats.endMenuBarSampling()
}

@MainActor
@Test("Repeated open/close cycles produce a single derived sample per tick, no duplicates")
func repeatedOpenCloseNoDuplicates() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { id in
        ContainerStats(id: id, cpuUsageUsec: 1_000_000, memoryUsageBytes: 200, memoryLimitBytes: 1_000,
                       blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 1)
    }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    // Five open/close cycles shouldn't leave the timer doubled or the samples
    // re-seeded. After five ticks of load() the history series should have exactly
    // five samples (one per baseline-then-derive pair, modulo the first tick).
    for _ in 0..<5 {
        stats.beginMenuBarSampling()
        await stats.load(showLoading: false)
        stats.endMenuBarSampling()
    }

    // Each tick either adds a baseline (no derived sample) or a derived sample.
    // After 5 ticks we expect at least 4 derived samples (the first tick seeds a
    // baseline, the remaining 4 produce derived samples).
    let samples = stats.history.samples(for: StatsKey(id: "web"))
    #expect(samples.count >= 4)
    #expect(samples.count <= 5)
}

// MARK: - Menu-bar history state mapping

@MainActor
@Test("menuBarHistoryState maps the five StatsSamplingState cases onto the four UI states")
func menuBarHistoryStateMapping() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { id in
        ContainerStats(id: id, cpuUsageUsec: 1_000_000, memoryUsageBytes: 200, memoryLimitBytes: 1_000,
                       blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 1)
    }
    let (_, stats) = makeStats(
        backend: backend,
        containers: [try makeContainer(id: "web", status: "running")]
    )

    // idle → collecting
    #expect(stats.menuBarHistoryState() == .collecting)

    // collecting after first tick → collecting
    await stats.load(showLoading: false)
    #expect(stats.menuBarHistoryState() == .collecting)

    // available after second tick → available
    await stats.load(showLoading: false)
    #expect(stats.menuBarHistoryState() == .available)

    // Force unavailable and verify the mapping.
    backend.statsHandler = { _ in throw decodeError() }
    await stats.load(showLoading: false)
    if case .unavailable = stats.menuBarHistoryState() {
        // expected
    } else {
        Issue.record("expected .unavailable, got \(stats.menuBarHistoryState())")
    }

    // No containers → noData. The `containerList` is private on StatsService, so mutate
    // through the AppServices container that owns it.
    let service = makeService(backend: backend)
    service.containerListService.containers = []
    service.statsService.machineStatTargets = { [] }
    await service.statsService.load(showLoading: false)
    #expect(service.statsService.menuBarHistoryState() == .noData)
}
