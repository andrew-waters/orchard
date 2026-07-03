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

    /// Per-container stats; throw to simulate a failure for that container.
    var statsHandler: (@Sendable (String) throws -> Orchard.ContainerStats)?

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
    func stats(id: String) async throws -> Orchard.ContainerStats {
        if let handler = statsHandler { return try handler(id) }
        throw NotConfigured()
    }
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

/// Decode a minimal `Container` fixture with the given id and status.
func makeContainer(id: String, status: String) throws -> Container {
    let json = """
    {
      "status": "\(status)",
      "networks": [],
      "configuration": {
        "id": "\(id)",
        "runtimeHandler": "vz",
        "rosetta": false,
        "labels": {},
        "sysctls": {},
        "publishedPorts": [],
        "mounts": [],
        "platform": { "os": "linux", "architecture": "arm64" },
        "image": {
          "reference": "nginx:latest",
          "descriptor": { "mediaType": "application/vnd.oci.image.index.v1+json", "digest": "sha256:abc", "size": 0 }
        },
        "dns": { "nameservers": [], "searchDomains": [], "options": [] },
        "resources": { "cpus": 1, "memoryInBytes": 1024 },
        "initProcess": {
          "terminal": false,
          "environment": [],
          "workingDirectory": "/",
          "arguments": [],
          "executable": "/bin/sh",
          "user": {},
          "rlimits": [],
          "supplementalGroups": []
        }
      }
    }
    """
    return try JSONDecoder().decode(Container.self, from: Data(json.utf8))
}

/// A single-builder `container builder status --format json` payload with the given status.
func makeBuilderStatusJSON(id: String = "buildkit", status: String) -> String {
    """
    {
      "status": "\(status)",
      "networks": [],
      "configuration": {
        "id": "\(id)",
        "rosetta": false,
        "runtimeHandler": "vz",
        "labels": {},
        "sysctls": {},
        "mounts": [],
        "networks": [],
        "platform": { "os": "linux", "architecture": "arm64" },
        "image": {
          "reference": "buildkit:latest",
          "descriptor": { "mediaType": "application/vnd.oci.image.index.v1+json", "digest": "sha256:abc", "size": 0 }
        },
        "dns": { "nameservers": [], "searchDomains": [], "options": [] },
        "resources": { "cpus": 2, "memoryInBytes": 2048 },
        "initProcess": {
          "terminal": false,
          "environment": [],
          "workingDirectory": "/",
          "arguments": [],
          "executable": "/bin/sh",
          "user": {},
          "rlimits": [],
          "supplementalGroups": []
        }
      }
    }
    """
}

/// A stats value with the given id and otherwise-zero fields.
func makeStats(id: String) -> Orchard.ContainerStats {
    Orchard.ContainerStats(
        id: id, cpuUsageUsec: 0, memoryUsageBytes: 0, memoryLimitBytes: 0,
        blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 0
    )
}

/// Convenience to build a service wired to mocks.
@MainActor
func makeService(
    backend: MockContainerBackend = MockContainerBackend(),
    runner: MockCommandRunner = MockCommandRunner()
) -> ContainerService {
    ContainerService(backend: backend, runner: runner)
}
