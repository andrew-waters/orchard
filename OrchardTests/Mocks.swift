import Foundation
@testable import Orchard

struct NotConfigured: Error {}

/// Records the last error and lets tests supply canned CLI output.
final class MockCommandRunner: CommandRunner, @unchecked Sendable {
    var defaultResult = ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    var runHandler: (@Sendable (String, [String]) throws -> ProcessResult)?
    private(set) var calls: [[String]] = []

    func run(program: String, arguments: [String]) async throws -> ProcessResult {
        calls.append(arguments)
        if let handler = runHandler { return try handler(program, arguments) }
        return defaultResult
    }

    func runWithSudo(program: String, arguments: [String]) async throws -> ProcessResult {
        try await run(program: program, arguments: arguments)
    }
}

/// A `ContainerBackend` whose behaviour is configured per test. Methods not needed by a
/// test either no-op or throw `NotConfigured`.
final class MockContainerBackend: ContainerBackend, @unchecked Sendable {
    var containers: [Container] = []
    var listContainersError: Error?
    var images: [ContainerImage] = []
    var networks: [ContainerNetwork] = []

    private(set) var createdSpecs: [ContainerCreateSpec] = []
    var createContainerError: Error?

    /// Called with the 1-based attempt count; throw to simulate a failed start.
    var bootstrapAndStartHandler: (@Sendable (Int) throws -> Void)?
    private(set) var bootstrapAndStartCount = 0

    func listContainers() async throws -> [Container] {
        if let error = listContainersError { throw error }
        return containers
    }
    func stopContainer(id: String) async throws {}
    func killContainer(id: String, signal: Int32) async throws {}
    func deleteContainer(id: String, force: Bool) async throws {}
    func bootstrapAndStart(id: String) async throws {
        bootstrapAndStartCount += 1
        try bootstrapAndStartHandler?(bootstrapAndStartCount)
    }
    func containerLogs(id: String) async throws -> [FileHandle] { [] }
    func stats(id: String) async throws -> Orchard.ContainerStats { throw NotConfigured() }
    func createContainer(_ spec: ContainerCreateSpec) async throws {
        createdSpecs.append(spec)
        if let error = createContainerError { throw error }
    }
    func listImages() async throws -> [ContainerImage] { images }
    func pullImage(reference: String) async throws {}
    func deleteImage(reference: String) async throws {}
    func inspectImage(reference: String) async throws -> ImageInspection { throw NotConfigured() }
    func listNetworks() async throws -> [ContainerNetwork] { networks }
    func createNetwork(name: String, labels: [String: String]) async throws {}
    func deleteNetwork(id: String) async throws {}
    func ping() async throws -> SystemHealthInfo { SystemHealthInfo(apiServerVersion: "test") }
    func diskUsage() async throws -> SystemDiskUsage { throw NotConfigured() }
}

/// Convenience to build a service wired to mocks.
@MainActor
func makeService(
    backend: MockContainerBackend = MockContainerBackend(),
    runner: MockCommandRunner = MockCommandRunner()
) -> ContainerService {
    ContainerService(backend: backend, runner: runner)
}
