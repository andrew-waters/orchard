import Testing
import Foundation
@testable import Orchard

// ContainerListService lifecycle, recovery, and retry logic. Focus is the branches
// beyond the two start cases in ContainerServiceTests: the stop/force-stop/remove failure
// handling and the auto-removal recovery + retry loop (the riskiest logic in the service).
//
// These construct ContainerListService directly (no facade) with `pollInterval: 0` so
// the fire-and-forget `refreshUntilContainer…` poll loops finish in microseconds instead
// of the 0.5s×10 production cadence — no real sleeps, and no ~5s task leaking past the test.
// Success paths await quiescence on the loading flag; the backend poll count distinguishes
// terminal-on-first-poll (1) from the timeout fallback (maxRefreshAttempts).
//
// Alert copy is not asserted (localized/brittle — same stance as ImageServiceTests);
// branches are distinguished structurally (loading flag, recoveryFailed set, poll/attempt
// counts, recorded specs).

/// A directly-constructed ContainerListService with its own AlertCenter and no poll delay.
@MainActor
private func makeListService(_ backend: MockContainerBackend = MockContainerBackend())
    -> (service: ContainerListService, alert: AlertCenter) {
    let alert = AlertCenter()
    let service = ContainerListService(backend: backend, alertCenter: alert, pollInterval: 0)
    return (service, alert)
}

/// Yield until `condition` holds or a bounded number of hops elapses. With `pollInterval = 0`
/// the spawned refresh loops complete in a handful of yields; the cap guards against a hang.
@MainActor
private func awaitQuiescence(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
}

// MARK: - stop / force-stop failure

@MainActor
@Test("stopContainer: a failure alerts and clears the loading state")
func stopContainerFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.stopContainerError = NotConfigured()
    let (service, alert) = makeListService(backend)

    await service.stopContainer("web")

    #expect(alert.current != nil)
    #expect(service.loadingContainers.contains("web") == false)
}

@MainActor
@Test("forceStopContainer: a failure alerts and clears the loading state")
func forceStopContainerFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.killContainerError = NotConfigured()
    let (service, alert) = makeListService(backend)

    await service.forceStopContainer("web")

    #expect(alert.current != nil)
    #expect(service.loadingContainers.contains("web") == false)
}

// MARK: - remove

@MainActor
@Test("removeContainer: success drops the container locally and clears loading")
func removeContainerSuccess() async throws {
    let backend = MockContainerBackend()
    let (service, alert) = makeListService(backend)
    service.containers = [
        try makeContainer(id: "gone", status: "stopped"),
        try makeContainer(id: "keep", status: "running"),
    ]

    await service.removeContainer("gone")

    #expect(backend.deletedContainers.contains { $0.id == "gone" && $0.force == false })
    #expect(service.containers.map(\.configuration.id) == ["keep"])
    #expect(service.loadingContainers.contains("gone") == false)
    #expect(alert.current == nil)
}

@MainActor
@Test("removeContainer: a failure alerts and clears loading")
func removeContainerFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteContainerError = NotConfigured()
    let (service, alert) = makeListService(backend)

    await service.removeContainer("stuck")

    #expect(alert.current != nil)
    #expect(service.loadingContainers.contains("stuck") == false)
}

@MainActor
@Test("removeContainers: removes every id in turn")
func removeContainersRemovesAll() async throws {
    let backend = MockContainerBackend()
    let (service, _) = makeListService(backend)
    service.containers = [
        try makeContainer(id: "a", status: "stopped"),
        try makeContainer(id: "b", status: "stopped"),
    ]

    await service.removeContainers(["a", "b"])

    #expect(backend.deletedContainers.map(\.id).sorted() == ["a", "b"])
    #expect(service.containers.isEmpty)
}

// MARK: - start error classification

@MainActor
@Test("startContainer: a generic error alerts once and does not retry")
func startContainerGenericErrorAlerts() async {
    let backend = MockContainerBackend()
    backend.bootstrapAndStartHandler = { _ in throw makeError("disk is on fire") }
    let (service, alert) = makeListService(backend)

    await service.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 1)   // generic → no retry
    #expect(alert.current != nil)
    // A generic failure is NOT the auto-removal path — it must not set the recovery flag.
    #expect(service.recoveryFailedContainerIDs.contains("web") == false)
    #expect(service.loadingContainers.contains("web") == false)
}

@MainActor
@Test("startContainer: a transition error retries then succeeds")
func startContainerTransitionThenSucceeds() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "running")]   // the eventual started state
    backend.bootstrapAndStartHandler = { attempt in
        if attempt == 1 { throw makeError("expected to be in created state / invalidState") }
        // attempt 2 succeeds
    }
    let (service, _) = makeListService(backend)

    await service.startContainer("web", maxRetries: 3, retryDelay: 0)
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    #expect(backend.bootstrapAndStartCount == 2)   // retried once, then started
    #expect(service.recoveryFailedContainerIDs.contains("web") == false)
}

// MARK: - auto-removal recovery

@MainActor
@Test("startContainer: 'not found' with no snapshot marks recovery failed and alerts")
func startContainerNotFoundNoSnapshotFailsRecovery() async {
    let backend = MockContainerBackend()
    backend.bootstrapAndStartHandler = { _ in throw makeError("container not found") }
    let (service, alert) = makeListService(backend)   // no prior loadContainers → no snapshot

    await service.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 1)   // recovery fails → no retry
    #expect(service.recoveryFailedContainerIDs.contains("web"))   // structural marker of this branch
    #expect(alert.current != nil)
    #expect(service.loadingContainers.contains("web") == false)
}

@MainActor
@Test("startContainer: 'not found' with a snapshot recreates the container from the snapshot")
func startContainerNotFoundRecreatesFromSnapshot() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "running")]
    let (service, _) = makeListService(backend)
    await service.loadContainers()   // seed the recovery snapshot

    // The container was auto-removed on the first (and only) start attempt.
    backend.bootstrapAndStartHandler = { _ in throw makeError("container not found") }

    await service.startContainer("web", maxRetries: 3, retryDelay: 0)
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    // Recovery recreates the container from the snapshot (createContainer also starts it)
    // and does NOT re-run bootstrapAndStart — so exactly one bootstrap attempt occurred
    // (the initial failure), and the branch isn't marked recovery-failed. Labels, resources,
    // and hostname aren't preserved (no field in the create path); see recoverContainer.
    #expect(backend.createdSpecs.contains { $0.id == "web" })
    #expect(backend.bootstrapAndStartCount == 1)   // no second start on the recovered container
    #expect(service.recoveryFailedContainerIDs.contains("web") == false)
}

// MARK: - refresh poll loops (driven through the public stop/start wiring)

@MainActor
@Test("stopContainer: the spawned poll loop clears loading on the first poll once stopped")
func stopRefreshClearsWhenStopped() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "stopped")]   // found, not running
    let (service, _) = makeListService(backend)

    await service.stopContainer("web")
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    #expect(service.loadingContainers.contains("web") == false)
    #expect(backend.listContainersCount == 1)   // terminal detected on the first poll, not via timeout
}

@MainActor
@Test("stopContainer: the spawned poll loop clears loading on the first poll once gone")
func stopRefreshClearsWhenAbsent() async {
    let backend = MockContainerBackend()   // container not in the list → treated as stopped
    let (service, _) = makeListService(backend)

    await service.stopContainer("web")
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    #expect(service.loadingContainers.contains("web") == false)
    #expect(backend.listContainersCount == 1)
}

@MainActor
@Test("startContainer: the spawned poll loop clears loading on the first poll once running")
func startRefreshClearsWhenRunning() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "running")]   // starts running
    let (service, _) = makeListService(backend)

    await service.startContainer("web", maxRetries: 1, retryDelay: 0)
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    #expect(service.loadingContainers.contains("web") == false)
    #expect(backend.listContainersCount == 1)   // running detected on the first poll
}

@MainActor
@Test("stopContainer: the poll loop times out after maxRefreshAttempts polls and still clears loading")
func stopRefreshTimesOut() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "running")]   // never reports stopped
    let (service, _) = makeListService(backend)

    await service.stopContainer("web")
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    // The timeout fallback (not the terminal return) clears loading after exhausting the polls.
    #expect(service.loadingContainers.contains("web") == false)
    #expect(backend.listContainersCount == service.maxRefreshAttempts)
}

// MARK: - recreate

@MainActor
@Test("recreateContainer: success force-deletes the old container and runs the new config")
func recreateContainerSuccess() async {
    let backend = MockContainerBackend()
    let (service, alert) = makeListService(backend)

    await service.recreateContainer(
        oldContainerId: "old", newConfig: ContainerRunConfig(name: "new", image: "nginx")
    )

    #expect(backend.deletedContainers.contains { $0.id == "old" && $0.force == true })
    #expect(backend.createdSpecs.contains { $0.id == "new" })
    #expect(alert.current == nil)
}

@MainActor
@Test("recreateContainer: a delete failure alerts and does not recreate")
func recreateContainerFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteContainerError = NotConfigured()
    let (service, alert) = makeListService(backend)

    await service.recreateContainer(
        oldContainerId: "old", newConfig: ContainerRunConfig(name: "new", image: "nginx")
    )

    #expect(alert.current != nil)
    #expect(backend.createdSpecs.isEmpty)   // never reached runContainer
}
