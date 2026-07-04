import Testing
import Foundation
@testable import Orchard

// ContainerListService lifecycle, recovery, and retry logic. Focus is the branches
// beyond the two start cases in ContainerServiceTests: the stop/force-stop/remove failure
// handling and the auto-removal recovery + retry loop (the riskiest logic in the service).
//
// The `refreshUntilContainerStarted/Stopped` poll loops are private and spawned as
// fire-and-forget Tasks by stopContainer/forceStopContainer/startContainer. Tests drive
// that PUBLIC wiring with `pollInterval = 0` (so the loops finish in microseconds instead
// of the 0.5s×10 production cadence), then await quiescence. The backend's poll count
// distinguishes terminal-on-first-poll (1 poll) from the timeout fallback (maxRefreshAttempts
// polls), so inverting the status check or dropping the timeout clear fails a test.

private func startError(_ message: String) -> NSError {
    NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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
    let service = makeService(backend: backend)

    await service.containerListService.stopContainer("web")

    #expect(service.alertCenter.current?.message.contains("Failed to stop container") == true)
    #expect(service.containerListService.loadingContainers.contains("web") == false)
}

@MainActor
@Test("forceStopContainer: a failure alerts and clears the loading state")
func forceStopContainerFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.killContainerError = NotConfigured()
    let service = makeService(backend: backend)

    await service.containerListService.forceStopContainer("web")

    #expect(service.alertCenter.current?.message.contains("Failed to force stop container") == true)
    #expect(service.containerListService.loadingContainers.contains("web") == false)
}

// MARK: - remove

@MainActor
@Test("removeContainer: success drops the container locally and clears loading")
func removeContainerSuccess() async throws {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    service.containerListService.containers = [
        try makeContainer(id: "gone", status: "stopped"),
        try makeContainer(id: "keep", status: "running"),
    ]

    await service.containerListService.removeContainer("gone")

    #expect(backend.deletedContainers.contains { $0.id == "gone" && $0.force == false })
    #expect(service.containerListService.containers.map(\.configuration.id) == ["keep"])
    #expect(service.containerListService.loadingContainers.contains("gone") == false)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("removeContainer: a failure alerts and clears loading")
func removeContainerFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteContainerError = NotConfigured()
    let service = makeService(backend: backend)

    await service.containerListService.removeContainer("stuck")

    #expect(service.alertCenter.current?.message.contains("Failed to remove container") == true)
    #expect(service.containerListService.loadingContainers.contains("stuck") == false)
}

@MainActor
@Test("removeContainers: removes every id in turn")
func removeContainersRemovesAll() async throws {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    service.containerListService.containers = [
        try makeContainer(id: "a", status: "stopped"),
        try makeContainer(id: "b", status: "stopped"),
    ]

    await service.containerListService.removeContainers(["a", "b"])

    #expect(backend.deletedContainers.map(\.id).sorted() == ["a", "b"])
    #expect(service.containerListService.containers.isEmpty)
}

// MARK: - start error classification

@MainActor
@Test("startContainer: a generic error alerts once and does not retry")
func startContainerGenericErrorAlerts() async {
    let backend = MockContainerBackend()
    backend.bootstrapAndStartHandler = { _ in throw startError("disk is on fire") }
    let service = makeService(backend: backend)

    await service.containerListService.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 1)   // generic → no retry
    #expect(service.alertCenter.current?.message.contains("Failed to start container") == true)
    #expect(service.containerListService.loadingContainers.contains("web") == false)
}

@MainActor
@Test("startContainer: a transition error retries then succeeds")
func startContainerTransitionThenSucceeds() async {
    let backend = MockContainerBackend()
    backend.bootstrapAndStartHandler = { attempt in
        if attempt == 1 { throw startError("expected to be in created state / invalidState") }
        // attempt 2 succeeds
    }
    let service = makeService(backend: backend)

    await service.containerListService.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 2)   // retried once, then started
    #expect(service.containerListService.recoveryFailedContainerIDs.contains("web") == false)
}

// MARK: - auto-removal recovery

@MainActor
@Test("startContainer: 'not found' with no snapshot marks recovery failed and alerts")
func startContainerNotFoundNoSnapshotFailsRecovery() async {
    let backend = MockContainerBackend()
    backend.bootstrapAndStartHandler = { _ in throw startError("container not found") }
    let service = makeService(backend: backend)   // no prior loadContainers → no snapshot

    await service.containerListService.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 1)   // recovery fails → no retry
    #expect(service.containerListService.recoveryFailedContainerIDs.contains("web"))
    #expect(service.alertCenter.current?.message.contains("could not be recovered") == true)
    #expect(service.containerListService.loadingContainers.contains("web") == false)
}

@MainActor
@Test("startContainer: 'not found' with a snapshot recovers, recreates, and retries to success")
func startContainerNotFoundRecoversAndRetries() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "running")]
    let service = makeService(backend: backend)
    await service.containerListService.loadContainers()   // seed the recovery snapshot

    // First start attempt: container was auto-removed. Recovery recreates it; retry starts it.
    backend.bootstrapAndStartHandler = { attempt in
        if attempt == 1 { throw startError("container not found") }
        // attempt 2 (post-recovery) succeeds
    }

    await service.containerListService.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 2)                                   // recovered then retried
    #expect(backend.createdSpecs.contains { $0.id == "web" })                      // recovery recreated it
    #expect(service.containerListService.recoveryFailedContainerIDs.contains("web") == false)
    #expect(service.alertCenter.current == nil)
}

// MARK: - refresh poll loops (driven through the public stop/start wiring)

@MainActor
@Test("stopContainer: the spawned poll loop clears loading on the first poll once stopped")
func stopRefreshClearsWhenStopped() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "stopped")]   // found, not running
    let service = ContainerListService(backend: backend, alertCenter: AlertCenter())
    service.pollInterval = 0

    await service.stopContainer("web")
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    #expect(service.loadingContainers.contains("web") == false)
    #expect(backend.listContainersCount == 1)   // terminal detected on the first poll, not via timeout
}

@MainActor
@Test("stopContainer: the spawned poll loop clears loading on the first poll once gone")
func stopRefreshClearsWhenAbsent() async {
    let backend = MockContainerBackend()   // container not in the list → treated as stopped
    let service = ContainerListService(backend: backend, alertCenter: AlertCenter())
    service.pollInterval = 0

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
    let service = ContainerListService(backend: backend, alertCenter: AlertCenter())
    service.pollInterval = 0

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
    let service = ContainerListService(backend: backend, alertCenter: AlertCenter())
    service.pollInterval = 0

    await service.stopContainer("web")
    await awaitQuiescence { !service.loadingContainers.contains("web") }

    // The timeout fallback (not the terminal return) clears loading after exhausting the polls.
    #expect(service.loadingContainers.contains("web") == false)
    #expect(backend.listContainersCount == 10)   // maxRefreshAttempts
}

// MARK: - recreate

@MainActor
@Test("recreateContainer: success force-deletes the old container and runs the new config")
func recreateContainerSuccess() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)

    await service.containerListService.recreateContainer(
        oldContainerId: "old", newConfig: ContainerRunConfig(name: "new", image: "nginx")
    )

    #expect(backend.deletedContainers.contains { $0.id == "old" && $0.force == true })
    #expect(backend.createdSpecs.contains { $0.id == "new" })
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("recreateContainer: a delete failure alerts and does not recreate")
func recreateContainerFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteContainerError = NotConfigured()
    let service = makeService(backend: backend)

    await service.containerListService.recreateContainer(
        oldContainerId: "old", newConfig: ContainerRunConfig(name: "new", image: "nginx")
    )

    #expect(service.alertCenter.current?.message.contains("Failed to recreate container") == true)
    #expect(backend.createdSpecs.isEmpty)   // never reached runContainer
}
