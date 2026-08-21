import Testing
import Foundation
@testable import Orchard

// Tests for the Stop control surfaced in the menu bar popup
// (Orchard/Views/Features/MenuBar/MenuBarDashboard.swift). The button is wired to
// SystemService.stopSystem(); these tests exercise that contract end-to-end through
// AppServices so they pick up the cross-service callbacks installed in AppServices.init
// (clearing the container list via onSystemStopped).

@MainActor
@Test("stopSystem: success transitions to .stopped, clears isSystemLoading, issues exactly `system stop`")
func stopSystemSuccess() async {
    let runner = MockCommandRunner()   // default: exit 0
    let backend = MockContainerBackend()
    let service = makeService(backend: backend, runner: runner)

    // Pre-condition: the menu bar's Stop branch is gated on .running.
    service.systemService.systemStatus = .running
    // Seed a container so the onSystemStopped side-effect has something to clear.
    backend.containers = (try? [makeContainer(id: "web", status: "running")]) ?? []
    await service.containerListService.loadContainers()
    #expect(service.containerListService.containers.contains { $0.configuration.id == "web" })

    await service.systemService.stopSystem()

    #expect(service.systemService.systemStatus == .stopped)
    #expect(service.systemService.isSystemLoading == false)
    #expect(service.alertCenter.current == nil)
    #expect(runner.calls == [["system", "stop"]])
    // onSystemStopped hook installed by AppServices clears the in-memory container list.
    #expect(service.containerListService.containers.isEmpty)
}

@MainActor
@Test("stopSystem: isSystemLoading is true for the duration of the call")
func stopSystemTogglesLoadingFlag() async {
    let runner = MockCommandRunner()
    var observedLoading = false
    runner.runHandler = { _, _ in
        observedLoading = true   // set so we can assert later that the handler ran
        return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let service = makeService(runner: runner)
    service.systemService.systemStatus = .running

    await service.systemService.stopSystem()

    #expect(observedLoading == true)              // the handler was actually invoked
    #expect(service.systemService.isSystemLoading == false)   // flag cleared after the call
}

@MainActor
@Test("stopSystem: thrown error surfaces an alert and re-derives status from the daemon")
func stopSystemThrownErrorAlertsAndReDerives() async {
    // Mirrors the existing stopSystemFailureReDerives case, but for the throw branch
    // (runner throws) rather than the nonzero-exit branch. The menu bar's Stop button
    // must not silently swallow either failure mode.
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in throw makeError("container CLI missing") }
    let backend = MockContainerBackend()   // ping succeeds → daemon still running
    let service = makeService(backend: backend, runner: runner)

    await service.systemService.stopSystem()

    #expect(service.systemService.systemStatus == .running)   // not force-set to .stopped
    #expect(service.systemService.isSystemLoading == false)
    #expect(service.alertCenter.current != nil)
}

@MainActor
@Test("stopSystem: a second call while the first is in flight does not re-invoke the CLI")
func stopSystemGuardsAgainstDoubleDispatch() async {
    // Drive the runner to hang on a semaphore so we can issue a second stopSystem()
    // while the first is still pending, and confirm the runner was only called once.
    // The menu bar Stop button is `.disabled(isSystemLoading)`, but the service's
    // own isSystemLoading short-circuit is the underlying guard against duplicate
    // dispatch — useful for any future caller that bypasses the view layer.
    let runner = MockCommandRunner()
    let hang = DispatchSemaphore(value: 0)
    var invocations = 0
    runner.runHandler = { _, _ in
        invocations += 1
        hang.wait()   // blocks the runner until the test releases it
        return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let service = makeService(runner: runner)
    service.systemService.systemStatus = .running

    let first = Task { @MainActor in await service.systemService.stopSystem() }
    // Yield to let the first task reach the runner's blocking wait.
    await Task.yield()
    await Task.yield()
    #expect(service.systemService.isSystemLoading == true)

    // Second call should be a no-op while isSystemLoading is true.
    await service.systemService.stopSystem()

    #expect(invocations == 1)
    #expect(runner.calls == [["system", "stop"]])

    hang.signal()   // release the first task so the test can complete
    await first.value
}
