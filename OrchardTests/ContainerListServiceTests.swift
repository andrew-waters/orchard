import Testing
import Foundation
@testable import Orchard

// ContainerListService lifecycle, recovery, and retry logic, driven through the facade's
// `containerListService`. Focus is the branches beyond the two start cases in
// ContainerServiceTests: the stop/force-stop/remove failure handling and the
// auto-removal recovery + retry loop (the riskiest logic in the service).
//
// The `refreshUntilContainerStarted/Stopped` poll loops (internal, so tests can await
// them directly instead of racing the fire-and-forget Tasks that spawn them) are covered
// for the terminal-state path — where they clear the loading flag on the first poll. The
// timeout fallback isn't asserted: it would require ~5s of real Task.sleep with no
// injectable knob, and its loading-clear is the same line as the terminal path's.

private func startError(_ message: String) -> NSError {
    NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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

// MARK: - refresh poll loops (terminal-state path)

@MainActor
@Test("refreshUntilContainerStarted: clears loading once the container is running")
func refreshStartedClearsWhenRunning() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "running")]
    let service = makeService(backend: backend)
    service.containerListService.loadingContainers.insert("web")

    await service.containerListService.refreshUntilContainerStarted("web")

    #expect(service.containerListService.loadingContainers.contains("web") == false)
}

@MainActor
@Test("refreshUntilContainerStopped: clears loading once the container is no longer running")
func refreshStoppedClearsWhenStopped() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "web", status: "stopped")]
    let service = makeService(backend: backend)
    service.containerListService.loadingContainers.insert("web")

    await service.containerListService.refreshUntilContainerStopped("web")

    #expect(service.containerListService.loadingContainers.contains("web") == false)
}

@MainActor
@Test("refreshUntilContainerStopped: clears loading once the container is gone")
func refreshStoppedClearsWhenAbsent() async {
    let backend = MockContainerBackend()   // no containers → treated as stopped
    let service = makeService(backend: backend)
    service.containerListService.loadingContainers.insert("web")

    await service.containerListService.refreshUntilContainerStopped("web")

    #expect(service.containerListService.loadingContainers.contains("web") == false)
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
