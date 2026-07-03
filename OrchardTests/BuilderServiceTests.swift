import Testing
import Foundation
@testable import Orchard

// BuilderService state transitions, driven through the facade's `builderService`.
// Backed by MockCommandRunner returning canned `container builder …` output.
// (parseBuilderStatus itself is covered directly in CLIParserTests; the "not running"
// load path is covered in ContainerServiceTests — these cover the remaining branches.)

private func isStatusCall(_ args: [String]) -> Bool { args.contains("status") }

// MARK: - loadBuilders

@MainActor
@Test("loadBuilders: a spawn failure degrades silently to .stopped")
func loadBuildersSpawnFailure() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in throw NotConfigured() }
    let service = makeService(runner: runner)

    await service.builderService.loadBuilders()

    #expect(service.builderService.builders.isEmpty)
    #expect(service.builderService.builderStatus == .stopped)
    #expect(service.builderService.isBuildersLoading == false)
    #expect(service.alertCenter.current == nil)   // poll-driven: never alerts
}

@MainActor
@Test("loadBuilders: a nonzero exit degrades silently to .stopped")
func loadBuildersNonzeroExit() async {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(exitCode: 1, stdout: nil, stderr: "boom")
    let service = makeService(runner: runner)

    await service.builderService.loadBuilders()

    #expect(service.builderService.builders.isEmpty)
    #expect(service.builderService.builderStatus == .stopped)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("loadBuilders: a running builder populates the list and sets .running")
func loadBuildersRunning() async {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(
        exitCode: 0, stdout: makeBuilderStatusJSON(status: "running"), stderr: nil
    )
    let service = makeService(runner: runner)

    await service.builderService.loadBuilders()

    #expect(service.builderService.builders.count == 1)
    #expect(service.builderService.builderStatus == .running)
    #expect(service.builderService.isBuildersLoading == false)
}

@MainActor
@Test("loadBuilders: undecodable JSON degrades silently to .stopped")
func loadBuildersDecodeFailure() async {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(exitCode: 0, stdout: "{ not valid builder json", stderr: nil)
    let service = makeService(runner: runner)

    await service.builderService.loadBuilders()

    #expect(service.builderService.builders.isEmpty)
    #expect(service.builderService.builderStatus == .stopped)
    #expect(service.alertCenter.current == nil)
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
    let service = makeService(runner: runner)

    await service.builderService.startBuilder()

    #expect(runner.calls.contains(["builder", "start"]))
    #expect(service.builderService.builders.count == 1)   // onSuccess reload ran
    #expect(service.builderService.builderStatus == .running)
    #expect(service.builderService.isBuilderLoading == false)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("startBuilder: a nonzero exit surfaces a cliFailed alert")
func startBuilderNonzeroExitAlerts() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, args in
        isStatusCall(args)
            ? ProcessResult(exitCode: 0, stdout: "builder is not running", stderr: nil)
            : ProcessResult(exitCode: 2, stdout: nil, stderr: "start failed")
    }
    let service = makeService(runner: runner)

    await service.builderService.startBuilder()

    #expect(service.alertCenter.current != nil)
    #expect(service.builderService.isBuilderLoading == false)
}

@MainActor
@Test("stopBuilder: a spawn failure surfaces a 'Failed to stop' alert")
func stopBuilderThrowAlerts() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, args in
        if isStatusCall(args) { return ProcessResult(exitCode: 0, stdout: "builder is not running", stderr: nil) }
        throw NotConfigured()
    }
    let service = makeService(runner: runner)

    await service.builderService.stopBuilder()

    #expect(service.alertCenter.current?.message.contains("Failed to stop builder") == true)
    #expect(service.builderService.isBuilderLoading == false)
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
    let service = makeService(runner: runner)
    await service.builderService.loadBuilders()          // seed a running builder
    #expect(service.builderService.builders.count == 1)

    await service.builderService.deleteBuilder()

    #expect(runner.calls.contains(["builder", "delete"]))
    #expect(service.builderService.builders.isEmpty)     // onSuccess clears unconditionally
    #expect(service.alertCenter.current == nil)
}
