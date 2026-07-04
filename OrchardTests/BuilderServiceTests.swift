import Testing
import Foundation
@testable import Orchard

// BuilderService state transitions, backed by MockCommandRunner returning canned
// `container builder …` output. parseBuilderStatus itself is covered directly in
// CLIParserTests; the "not running" load path is covered in ContainerServiceTests.

private func isStatusCall(_ args: [String]) -> Bool { args.contains("status") }

/// A directly-constructed BuilderService (its SettingsStore backed by a throwaway suite).
@MainActor
private func makeBuilderService(_ runner: MockCommandRunner) -> (service: BuilderService, alert: AlertCenter) {
    let alert = AlertCenter()
    let settings = SettingsStore(alertCenter: alert, defaults: ephemeralDefaults())
    return (BuilderService(runner: runner, settings: settings, alertCenter: alert), alert)
}

// MARK: - loadBuilders

/// The three ways `container builder status` can fail to yield usable output. All degrade
/// to `.stopped` with no alert (poll-driven). NB the decode case is a KNOWN-ISSUE: a
/// zero-exit schema change leaves the state *unknown*, but we report it as definitively
/// stopped (see BuilderService.loadBuilders).
enum BuilderStatusDegrade: CaseIterable {
    case spawnFailure, nonzeroExit, decodeFailure

    func configure(_ runner: MockCommandRunner) {
        switch self {
        case .spawnFailure:
            runner.runHandler = { _, _ in throw NotConfigured() }
        case .nonzeroExit:
            runner.defaultResult = ProcessResult(exitCode: 1, stdout: nil, stderr: "boom")
        case .decodeFailure:
            runner.defaultResult = ProcessResult(exitCode: 0, stdout: "{ not valid builder json", stderr: nil)
        }
    }
}

@MainActor
@Test("loadBuilders degrades silently to .stopped", arguments: BuilderStatusDegrade.allCases)
func loadBuildersDegradesSilently(_ scenario: BuilderStatusDegrade) async {
    let runner = MockCommandRunner()
    scenario.configure(runner)
    let (service, alert) = makeBuilderService(runner)

    await service.loadBuilders()

    #expect(service.builders.isEmpty)
    #expect(service.builderStatus == .stopped)
    #expect(service.isBuildersLoading == false)
    #expect(alert.current == nil)   // poll-driven: never alerts
}

@MainActor
@Test("loadBuilders: a running builder populates the list and sets .running")
func loadBuildersRunning() async {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(
        exitCode: 0, stdout: makeBuilderStatusJSON(status: "running"), stderr: nil
    )
    let (service, _) = makeBuilderService(runner)

    await service.loadBuilders()

    #expect(service.builders.count == 1)
    #expect(service.builderStatus == .running)
    #expect(service.isBuildersLoading == false)
}

// MARK: - start / stop / delete

@MainActor
@Test("startBuilder: success reloads builders with no alert")
func startBuilderSuccess() async {
    let runner = MockCommandRunner()
    // `start` succeeds; the follow-up `status` reload reports a running builder.
    runner.runHandler = { _, args in
        if isStatusCall(args) {
            return ProcessResult(exitCode: 0, stdout: makeBuilderStatusJSON(status: "running"), stderr: nil)
        }
        return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let (service, alert) = makeBuilderService(runner)

    await service.startBuilder()

    #expect(runner.calls.contains(["builder", "start"]))
    #expect(service.builders.count == 1)   // onSuccess reload ran
    #expect(service.builderStatus == .running)
    #expect(service.isBuilderLoading == false)
    #expect(alert.current == nil)
}

@MainActor
@Test("startBuilder: a nonzero exit surfaces an alert")
func startBuilderNonzeroExitAlerts() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, args in
        isStatusCall(args)
            ? ProcessResult(exitCode: 0, stdout: "builder is not running", stderr: nil)
            : ProcessResult(exitCode: 2, stdout: nil, stderr: "start failed")
    }
    let (service, alert) = makeBuilderService(runner)

    await service.startBuilder()

    #expect(alert.current != nil)
    #expect(service.isBuilderLoading == false)
}

@MainActor
@Test("stopBuilder: a spawn failure surfaces an alert")
func stopBuilderThrowAlerts() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, args in
        if isStatusCall(args) { return ProcessResult(exitCode: 0, stdout: "builder is not running", stderr: nil) }
        throw NotConfigured()
    }
    let (service, alert) = makeBuilderService(runner)

    await service.stopBuilder()

    #expect(alert.current != nil)
    #expect(service.isBuilderLoading == false)
}

@MainActor
@Test("deleteBuilder: success clears the builder list")
func deleteBuilderSuccessClears() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, args in
        isStatusCall(args)
            ? ProcessResult(exitCode: 0, stdout: makeBuilderStatusJSON(status: "running"), stderr: nil)
            : ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let (service, alert) = makeBuilderService(runner)
    await service.loadBuilders()          // seed a running builder
    #expect(service.builders.count == 1)

    await service.deleteBuilder()

    #expect(runner.calls.contains(["builder", "delete"]))
    #expect(service.builders.isEmpty)     // onSuccess clears unconditionally
    #expect(alert.current == nil)
}
