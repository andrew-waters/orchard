import Foundation
import Testing
@testable import Orchard

// MARK: - Argument construction

@Test("ImageBuildService: arguments map the request onto container build flags")
func buildArguments() {
    let request = ImageBuildService.Request(
        dockerfile: "/proj/Dockerfile.dev", contextDir: "/proj", tag: "myapp:latest",
        arch: "arm64", noCache: false
    )
    #expect(ImageBuildService.arguments(for: request) == [
        "build",
        "--file", "/proj/Dockerfile.dev",
        "--tag", "myapp:latest",
        "--arch", "arm64",
        "--progress", "plain",
        "/proj",
    ])
}

@Test("ImageBuildService: no-cache adds the flag and the context stays last")
func buildArgumentsNoCache() {
    let request = ImageBuildService.Request(
        dockerfile: "/p/Dockerfile", contextDir: "/p", tag: "a", arch: "amd64", noCache: true
    )
    let arguments = ImageBuildService.arguments(for: request)
    #expect(arguments.contains("--no-cache"))
    #expect(arguments.last == "/p")
}

// MARK: - Validation

private func temporaryBuildContext() throws -> (dockerfile: String, context: String) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("orchard-build-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dockerfile = dir.appendingPathComponent("Dockerfile")
    try "FROM scratch\n".write(to: dockerfile, atomically: true, encoding: .utf8)
    return (dockerfile.path, dir.path)
}

@Test("ImageBuildService: a complete request validates")
func validationAccepts() throws {
    let (dockerfile, context) = try temporaryBuildContext()
    defer { try? FileManager.default.removeItem(atPath: context) }
    let request = ImageBuildService.Request(
        dockerfile: dockerfile, contextDir: context, tag: "myapp:v1.0", arch: "arm64", noCache: false
    )
    #expect(ImageBuildService.validationError(for: request) == nil)
}

@Test("ImageBuildService: each missing or wrong field gets its own message")
func validationRejects() throws {
    let (dockerfile, context) = try temporaryBuildContext()
    defer { try? FileManager.default.removeItem(atPath: context) }

    let valid = ImageBuildService.Request(
        dockerfile: dockerfile, contextDir: context, tag: "myapp", arch: "arm64", noCache: false
    )

    var request = valid
    request.dockerfile = ""
    #expect(ImageBuildService.validationError(for: request)?.contains("Dockerfile") == true)

    request = valid
    request.dockerfile = context // a directory, not a file
    #expect(ImageBuildService.validationError(for: request)?.contains("Dockerfile") == true)

    request = valid
    request.contextDir = ""
    #expect(ImageBuildService.validationError(for: request)?.contains("context") == true)

    request = valid
    request.contextDir = dockerfile // a file, not a directory
    #expect(ImageBuildService.validationError(for: request)?.contains("context") == true)

    request = valid
    request.tag = ""
    #expect(ImageBuildService.validationError(for: request)?.contains("Name") == true)

    for badTag in ["MyApp", "-app", "my app", "app::x"] {
        request = valid
        request.tag = badTag
        #expect(ImageBuildService.validationError(for: request) != nil, "expected rejection for \(badTag)")
    }

    for goodTag in ["myapp", "myapp:latest", "registry.local/team/app:V1.2-rc_3"] {
        request = valid
        request.tag = goodTag
        #expect(ImageBuildService.validationError(for: request) == nil, "expected acceptance for \(goodTag)")
    }
}

// MARK: - Failure summary

@Test("ImageBuildService: failure summary prefers the last stderr line, else exit code")
func buildFailureSummary() {
    let withStderr = ProcessResult(exitCode: 1, stdout: nil, stderr: "step 1 ok\nERROR: no such file\n  ")
    #expect(ImageBuildService.failureSummary(from: withStderr) == "ERROR: no such file")

    let silent = ProcessResult(exitCode: 17, stdout: nil, stderr: nil)
    #expect(ImageBuildService.failureSummary(from: silent).contains("17"))
}

// MARK: - Build lifecycle (mock runner)

@MainActor
private func awaitFinished(_ service: ImageBuildService, _ id: UUID) async {
    for _ in 0..<200 where service.build(id: id)?.phase == .building {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

/// A persistence target in a throwaway location, so tests never touch the real
/// Application Support registry.
private func ephemeralPersistence() -> BuildsPersistence {
    BuildsPersistence(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("orchard-builds-test-\(UUID().uuidString).json"))
}

@MainActor
private func makeBuildService(
    _ runner: MockCommandRunner,
    persistence: BuildsPersistence? = nil
) -> ImageBuildService {
    let services = makeService(runner: runner)
    return ImageBuildService(runner: runner, settings: services.settings, persistence: persistence ?? ephemeralPersistence())
}

@MainActor
@Test("ImageBuildService: a successful build finishes its record and refreshes images")
func buildSuccessLifecycle() async throws {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(exitCode: 0, stdout: "#1 building\n#1 DONE", stderr: nil)
    let service = makeBuildService(runner)

    let refreshed = SendableBox(false)
    service.onImageBuilt = { refreshed.value = true }

    let (dockerfile, context) = try temporaryBuildContext()
    defer { try? FileManager.default.removeItem(atPath: context) }
    let id = service.startBuild(.init(dockerfile: dockerfile, contextDir: context, tag: "t", arch: "arm64", noCache: false))
    #expect(service.build(id: id)?.phase == .building)
    #expect(service.runningCount == 1)

    await awaitFinished(service, id)
    #expect(service.build(id: id)?.phase == .succeeded)
    #expect(service.build(id: id)?.finishedAt != nil)
    #expect(refreshed.value)
    #expect(service.build(id: id)?.outputLines.contains("#1 DONE") == true)
    #expect(runner.calls.first?.first == "build")
}

@MainActor
@Test("ImageBuildService: a failing build surfaces the last stderr line on its record")
func buildFailureLifecycle() async throws {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(exitCode: 1, stdout: nil, stderr: "ERROR: exit code 127")
    let service = makeBuildService(runner)

    let (dockerfile, context) = try temporaryBuildContext()
    defer { try? FileManager.default.removeItem(atPath: context) }
    let id = service.startBuild(.init(dockerfile: dockerfile, contextDir: context, tag: "t", arch: "arm64", noCache: false))

    await awaitFinished(service, id)
    #expect(service.build(id: id)?.phase == .failed("ERROR: exit code 127"))
}

@MainActor
@Test("ImageBuildService: builds run concurrently and keep separate records")
func buildRegistryConcurrent() async throws {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(exitCode: 0, stdout: "ok", stderr: nil)
    let service = makeBuildService(runner)

    let (dockerfile, context) = try temporaryBuildContext()
    defer { try? FileManager.default.removeItem(atPath: context) }
    let first = service.startBuild(.init(dockerfile: dockerfile, contextDir: context, tag: "one", arch: "arm64", noCache: false))
    let second = service.startBuild(.init(dockerfile: dockerfile, contextDir: context, tag: "two", arch: "arm64", noCache: false))

    // Newest first, distinct records.
    #expect(service.builds.map(\.tag) == ["two", "one"])
    await awaitFinished(service, first)
    await awaitFinished(service, second)
    #expect(service.builds.allSatisfy { $0.phase == .succeeded })

    // clearFinished drops both, leaving an empty registry.
    service.clearFinished()
    #expect(service.builds.isEmpty)
}

@MainActor
@Test("ImageBuildService: cancel finalizes the record as cancelled, not failed")
func buildCancelLifecycle() async throws {
    let runner = MockCommandRunner()
    // A handler that never returns until cancelled keeps the build in flight.
    runner.runHandler = { _, _ in
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw CancellationError()
    }
    let service = makeBuildService(runner)

    let (dockerfile, context) = try temporaryBuildContext()
    defer { try? FileManager.default.removeItem(atPath: context) }
    let id = service.startBuild(.init(dockerfile: dockerfile, contextDir: context, tag: "t", arch: "arm64", noCache: false))
    #expect(service.build(id: id)?.phase == .building)

    service.cancel(id)
    #expect(service.build(id: id)?.phase == .cancelled)
    #expect(service.build(id: id)?.outputLines.last == "Build cancelled.")

    // The abandoned task must not overwrite the cancelled record.
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(service.build(id: id)?.phase == .cancelled)
    #expect(service.runningCount == 0)
}

// MARK: - Persistence

@MainActor
@Test("ImageBuildService: records survive a relaunch, with running builds marked interrupted")
func buildRegistryPersists() async throws {
    let persistence = ephemeralPersistence()
    defer { try? FileManager.default.removeItem(at: persistence.fileURL) }

    let (dockerfile, context) = try temporaryBuildContext()
    defer { try? FileManager.default.removeItem(atPath: context) }

    // First "launch": one finished build, one still running at quit.
    let finishRunner = MockCommandRunner()
    finishRunner.defaultResult = ProcessResult(exitCode: 0, stdout: "done", stderr: nil)
    let first = makeBuildService(finishRunner, persistence: persistence)
    let finishedID = first.startBuild(.init(dockerfile: dockerfile, contextDir: context, tag: "done:1", arch: "arm64", noCache: false))
    await awaitFinished(first, finishedID)

    let hangRunner = MockCommandRunner()
    hangRunner.runHandler = { _, _ in
        while !Task.isCancelled { try await Task.sleep(nanoseconds: 5_000_000) }
        throw CancellationError()
    }
    let stillRunning = makeBuildService(hangRunner, persistence: persistence)
    stillRunning.startBuild(.init(dockerfile: dockerfile, contextDir: context, tag: "hung:1", arch: "arm64", noCache: false))
    // (Quit here: nothing finalizes the running record.)

    // Second "launch" reloads the registry.
    let restored = makeBuildService(MockCommandRunner(), persistence: persistence)
    let phasesByTag = Dictionary(uniqueKeysWithValues: restored.builds.map { ($0.tag, $0.phase) })
    #expect(phasesByTag["hung:1"] == .interrupted)
    #expect(restored.builds.first { $0.tag == "hung:1" }?.outputLines.last?.contains("quit while this build was running") == true)
    #expect(restored.builds.first { $0.tag == "hung:1" }?.finishedAt != nil)
    #expect(restored.runningCount == 0)

    // The second instance loaded the first's records before adding its own,
    // so the finished build carried through both relaunches.
    #expect(phasesByTag["done:1"] == .succeeded)
    #expect(restored.builds.map(\.tag) == ["hung:1", "done:1"])
}

@Test("BuildsPersistence: round-trips records and trims persisted transcripts")
func buildsPersistenceRoundTrip() throws {
    let persistence = ephemeralPersistence()
    defer { try? FileManager.default.removeItem(at: persistence.fileURL) }

    var build = ImageBuild(
        id: UUID(),
        request: .init(dockerfile: "/d", contextDir: "/c", tag: "t:1", arch: "arm64", noCache: true),
        startedAt: Date(timeIntervalSince1970: 1_000_000)
    )
    build.phase = .failed("boom")
    build.finishedAt = Date(timeIntervalSince1970: 1_000_060)
    build.outputLines = (0..<(BuildsPersistence.persistedTranscriptLines + 500)).map { "line \($0)" }

    try persistence.save([build])
    let loaded = persistence.load()

    #expect(loaded.count == 1)
    #expect(loaded[0].id == build.id)
    #expect(loaded[0].phase == .failed("boom"))
    #expect(loaded[0].request == build.request)
    #expect(loaded[0].outputLines.count == BuildsPersistence.persistedTranscriptLines)
    #expect(loaded[0].outputLines.last == "line \(BuildsPersistence.persistedTranscriptLines + 499)")

    // Missing file and version mismatch both load as empty.
    #expect(BuildsPersistence(fileURL: persistence.fileURL.appendingPathExtension("missing")).load().isEmpty)
}

/// Tiny reference box for observing a callback from a Sendable closure in tests.
private final class SendableBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

// MARK: - Streaming runner (real processes)

@Test("SystemCommandRunner: runStreaming delivers lines live and the full transcript at exit")
func runStreamingRealProcess() async throws {
    let runner = SystemCommandRunner()
    let collected = LockedLines()
    let result = try await runner.runStreaming(
        program: "/bin/sh",
        arguments: ["-c", "printf 'one\\ntwo\\n'; printf 'err\\n' 1>&2; printf 'tail-no-newline'; exit 3"]
    ) { line in
        collected.append(line)
    }

    #expect(result.exitCode == 3)
    #expect(result.failed)
    #expect(result.stdout?.contains("one") == true)
    #expect(result.stdout?.contains("tail-no-newline") == true)
    #expect(result.stderr == "err")
    let lines = collected.snapshot()
    #expect(lines.contains("one"))
    #expect(lines.contains("two"))
    #expect(lines.contains("err"))
    #expect(lines.contains("tail-no-newline"))
}

@Test("SystemCommandRunner: cancelling runStreaming terminates the process")
func runStreamingCancellation() async throws {
    let runner = SystemCommandRunner()
    let task = Task {
        try await runner.runStreaming(program: "/bin/sleep", arguments: ["30"]) { _ in }
    }
    try await Task.sleep(nanoseconds: 200_000_000)
    task.cancel()

    let start = Date()
    let result = try? await task.value
    // SIGTERM exits promptly - nowhere near sleep's 30s - with a nonzero status.
    #expect(Date().timeIntervalSince(start) < 5)
    if let result {
        #expect(result.exitCode != 0)
    }
}

private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    func snapshot() -> [String] { lock.withLock { lines } }
}
