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
    let service = makeService(runner: runner)
    service.systemService.systemStatus = .running

    let observed = LockedBox<Bool?>(nil)
    runner.runHandler = { _, _ in
        // The CLI handler runs off the main actor; capture the loading flag via an
        // awaited main-actor hop so the test can safely read `observed.value` after
        // `stopSystem()` returns.
        await MainActor.run {
            observed.set(service.systemService.isSystemLoading)
        }
        return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }

    await service.systemService.stopSystem()

    #expect(observed.value == true)               // handler ran while loading flag was set
    #expect(service.systemService.isSystemLoading == false)   // flag cleared after the call
}

/// Locked box for one observation captured by a `@Sendable` test handler.
private final class LockedBox<T> {
    private let lock = NSLock()
    private var _value: T
    var value: T { lock.withLock { _value } }
    init(_ value: T) { self._value = value }
    func set(_ value: T) { lock.withLock { self._value = value } }
}

/// A one-shot awaitable gate for tests: `wait()` suspends without blocking a thread until
/// `open()` is called. Once open, later `wait()`s return immediately. Replaces the
/// semaphore pattern, whose blocking waits are unsafe in `@MainActor` async tests.
private final class TestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
    }
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
    // Hold the runner on a gate so we can issue a second stopSystem() while the first
    // is still pending, and confirm the runner was only called once. The menu bar Stop
    // button is `.disabled(isSystemLoading)`, but the service's own isSystemLoading
    // short-circuit is the underlying guard against duplicate dispatch — useful for
    // any future caller that bypasses the view layer.
    let runner = MockCommandRunner()
    let handlerEntered = TestGate()
    let releaseRunner = TestGate()
    runner.runHandler = { _, _ in
        handlerEntered.open()
        await releaseRunner.wait()   // holds the runner until the test releases it
        return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let service = makeService(runner: runner)
    service.systemService.systemStatus = .running

    let first = Task { @MainActor in await service.systemService.stopSystem() }
    // Suspends until the first task is actually inside the runner — no yield guessing.
    // isSystemLoading was set before the runner await, and the call is already recorded.
    await handlerEntered.wait()
    #expect(service.systemService.isSystemLoading == true)

    // Second call should be a no-op while isSystemLoading is true.
    await service.systemService.stopSystem()

    #expect(runner.calls == [["system", "stop"]])

    releaseRunner.open()   // release the first task so the test can complete
    await first.value
}

@MainActor
@Test("stopSystem: a stale in-flight checkSystemStatus ping doesn't flip .stopped back to .running")
func stopSystemIgnoresStaleStatusPing() async {
    // Simulates the menu-bar race: a 5s status-refresh tick starts a `checkSystemStatus`
    // (a `backend.ping()`) before the user clicks Stop. While that ping is held in
    // flight, Stop completes and transitions the state to .stopped. Releasing the ping
    // afterwards must NOT let its stale `.running` result overwrite .stopped.
    let runner = MockCommandRunner()
    let backend = MockContainerBackend()
    let pingStarted = TestGate()
    let releasePing = TestGate()
    backend.pingHandler = {
        pingStarted.open()
        await releasePing.wait()
        return SystemHealthInfo(apiServerVersion: "test")
    }
    let service = makeService(backend: backend, runner: runner)
    service.systemService.systemStatus = .running

    // Kick off the stale check and let it reach the held ping.
    let checkTask = Task { @MainActor in await service.systemService.checkSystemStatus() }
    await pingStarted.wait()   // confirm the ping is actually in flight before we Stop

    // Stop completes synchronously here (default MockCommandRunner returns success).
    await service.systemService.stopSystem()
    #expect(service.systemService.systemStatus == .stopped)

    // Release the held ping; the stale check resumes and would otherwise re-set .running.
    releasePing.open()
    await checkTask.value

    #expect(service.systemService.systemStatus == .stopped)
}
