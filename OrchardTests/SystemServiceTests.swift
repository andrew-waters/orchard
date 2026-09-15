import Testing
import Foundation
@testable import Orchard

@MainActor
@Test("startSystem: success transitions to .running")
func startSystemSuccess() async {
    let runner = MockCommandRunner()   // default result: exit 0
    let service = makeService(runner: runner)

    await service.systemService.startSystem()

    #expect(service.systemService.systemStatus == .running)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("startSystem: nonzero exit alerts and re-derives status instead of forcing .running")
func startSystemFailureReDerives() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 1, stdout: nil, stderr: "boom") }
    let backend = MockContainerBackend()
    backend.pingError = NotConfigured()   // daemon really is down → re-derive to .stopped
    let service = makeService(backend: backend, runner: runner)

    await service.systemService.startSystem()

    #expect(service.systemService.systemStatus == .stopped)   // NOT forced to .running
    #expect(service.alertCenter.current != nil)
}

@MainActor
@Test("stopSystem: nonzero exit alerts and does not force .stopped")
func stopSystemFailureReDerives() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 1, stdout: nil, stderr: "boom") }
    let backend = MockContainerBackend()   // ping succeeds → daemon still running
    let service = makeService(backend: backend, runner: runner)

    await service.systemService.stopSystem()

    #expect(service.systemService.systemStatus == .running)   // re-derived, not forced .stopped
    #expect(service.alertCenter.current != nil)
}

@MainActor
@Test("checkSystemStatus: undecodable health check gates on version, not .stopped")
func checkSystemStatusVersionMismatch() async {
    let backend = MockContainerBackend()
    backend.pingError = NSError(
        domain: "test", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "internalError: \"failed to decode apiServerBuild in health check\""])
    let service = makeService(backend: backend)

    await service.systemService.checkSystemStatus()

    #expect(service.systemService.systemStatus == .unsupportedVersion)
    #expect(service.systemService.systemStatusError?.isEmpty == false)
}

@MainActor
@Test("startSystem: a version mismatch stops the readiness poll without an outage alert")
func startSystemVersionMismatchGates() async {
    let runner = MockCommandRunner()   // `system start` exits 0
    let backend = MockContainerBackend()
    backend.pingError = NSError(
        domain: "test", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "failed to decode apiServerBuild in health check"])
    let service = makeService(backend: backend, runner: runner)

    await service.systemService.startSystem()

    #expect(service.systemService.systemStatus == .unsupportedVersion)
    #expect(service.alertCenter.current == nil)   // gated by the version screen, not an alert
    #expect(service.systemService.isSystemLoading == false)
    #expect(backend.pingCount == 1)   // mismatch is terminal: no retry sleeps
}

// MARK: - Recommended kernel

@MainActor
@Test("Recommended kernel: an already-installed refusal is retried with --force, not called success")
func setRecommendedKernelRetriesWithForce() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, arguments in
        // The CLI refuses to replace a kernel it already has unless forced. Reporting that as
        // success would leave a pre-nftables kernel in place, which is exactly the state this
        // action exists to get out of (apple/container#905).
        guard arguments.contains("--force") else {
            return ProcessResult(exitCode: 1, stdout: nil, stderr: "item with the same name already exists")
        }
        return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let service = makeService(runner: runner)

    await service.systemService.setRecommendedKernel()

    #expect(runner.calls.contains(["system", "kernel", "set", "--recommended"]))
    #expect(runner.calls.contains(["system", "kernel", "set", "--recommended", "--force"]))
    #expect(service.systemService.kernelConfig.isRecommended)
    #expect(service.systemService.isKernelLoading == false)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("Recommended kernel: a forced retry that still fails surfaces the error")
func setRecommendedKernelForcedFailureAlerts() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in
        ProcessResult(exitCode: 1, stdout: nil, stderr: "item with the same name already exists")
    }
    let service = makeService(runner: runner)

    await service.systemService.setRecommendedKernel()

    #expect(runner.calls.count == 2)   // tried, then forced
    #expect(service.systemService.kernelConfig.isRecommended == false)
    #expect(service.systemService.isKernelLoading == false)
    #expect(service.alertCenter.current != nil)
}

@MainActor
@Test("Recommended kernel: a clean install needs no forced retry")
func setRecommendedKernelSucceedsFirstTime() async {
    let runner = MockCommandRunner()   // default result: exit 0
    let service = makeService(runner: runner)

    await service.systemService.setRecommendedKernel()

    #expect(runner.calls == [["system", "kernel", "set", "--recommended"]])
    #expect(service.systemService.kernelConfig.isRecommended)
    #expect(service.alertCenter.current == nil)
}
