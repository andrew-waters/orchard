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
    var listImagesError: Error?
    var pullImageError: Error?
    var deleteImageError: Error?
    private(set) var pulledReferences: [String] = []
    private(set) var deletedImageReferences: [String] = []
    var networks: [ContainerNetwork] = []
    var listNetworksError: Error?
    var createNetworkError: Error?
    var deleteNetworkError: Error?
    private(set) var createdNetworks: [(name: String, labels: [String: String])] = []
    private(set) var deletedNetworkIds: [String] = []

    private(set) var createdSpecs: [ContainerCreateSpec] = []
    var createContainerError: Error?

    /// Called with the 1-based attempt count; throw to simulate a failed start.
    var bootstrapAndStartHandler: (@Sendable (Int) throws -> Void)?
    private(set) var bootstrapAndStartCount = 0

    /// Per-container stats; throw to simulate a failure for that container.
    var statsHandler: (@Sendable (String) throws -> Orchard.ContainerStats)?

    private(set) var listContainersCount = 0
    func listContainers() async throws -> [Container] {
        listContainersCount += 1
        if let error = listContainersError { throw error }
        return containers
    }
    var stopContainerError: Error?
    var killContainerError: Error?
    var deleteContainerError: Error?
    private(set) var deletedContainers: [(id: String, force: Bool)] = []
    func stopContainer(id: String) async throws {
        if let stopContainerError { throw stopContainerError }
    }
    func killContainer(id: String, signal: Int32) async throws {
        if let killContainerError { throw killContainerError }
    }
    func deleteContainer(id: String, force: Bool) async throws {
        deletedContainers.append((id: id, force: force))
        if let deleteContainerError { throw deleteContainerError }
    }
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
    func listImages() async throws -> [ContainerImage] {
        if let listImagesError { throw listImagesError }
        return images
    }
    func pullImage(reference: String) async throws {
        pulledReferences.append(reference)
        if let pullImageError { throw pullImageError }
    }
    func deleteImage(reference: String) async throws {
        deletedImageReferences.append(reference)
        if let deleteImageError { throw deleteImageError }
    }
    func inspectImage(reference: String) async throws -> ImageInspection { throw NotConfigured() }
    func listNetworks() async throws -> [ContainerNetwork] {
        if let listNetworksError { throw listNetworksError }
        return networks
    }
    func createNetwork(name: String, labels: [String: String]) async throws {
        createdNetworks.append((name: name, labels: labels))
        if let createNetworkError { throw createNetworkError }
    }
    func deleteNetwork(id: String) async throws {
        deletedNetworkIds.append(id)
        if let deleteNetworkError { throw deleteNetworkError }
    }
    var pingError: Error?
    func ping() async throws -> SystemHealthInfo {
        if let pingError { throw pingError }
        return SystemHealthInfo(apiServerVersion: "test")
    }
    func diskUsage() async throws -> SystemDiskUsage { throw NotConfigured() }
}

/// Decode a minimal `Container` fixture with the given id and status.
// Shared JSON fragments for the Container / Builder fixtures (their configuration
// shapes differ, but these sub-objects are identical).
private let fixturePlatformJSON = #"{ "os": "linux", "architecture": "arm64" }"#
private let fixtureDNSJSON = #"{ "nameservers": [], "searchDomains": [], "options": [] }"#
private let fixtureInitProcessJSON = """
{ "terminal": false, "environment": [], "workingDirectory": "/", "arguments": [], \
"executable": "/bin/sh", "user": {}, "rlimits": [], "supplementalGroups": [] }
"""
private func fixtureImageJSON(_ reference: String) -> String {
    #"{ "reference": "\#(reference)", "descriptor": { "mediaType": "application/vnd.oci.image.index.v1+json", "digest": "sha256:abc", "size": 0 } }"#
}

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
        "platform": \(fixturePlatformJSON),
        "image": \(fixtureImageJSON("nginx:latest")),
        "dns": \(fixtureDNSJSON),
        "resources": { "cpus": 1, "memoryInBytes": 1024 },
        "initProcess": \(fixtureInitProcessJSON)
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
        "platform": \(fixturePlatformJSON),
        "image": \(fixtureImageJSON("buildkit:latest")),
        "dns": \(fixtureDNSJSON),
        "resources": { "cpus": 2, "memoryInBytes": 2048 },
        "initProcess": \(fixtureInitProcessJSON)
      }
    }
    """
}

/// A `ContainerImage` fixture with the given reference and otherwise-empty descriptor.
func makeImage(reference: String) -> ContainerImage {
    ContainerImage(
        descriptor: ContainerImageDescriptor(
            digest: "sha256:abc", mediaType: "application/vnd.oci.image.index.v1+json",
            size: 0, annotations: nil
        ),
        reference: reference
    )
}

/// A `ContainerNetwork` fixture with the given id and otherwise-empty fields.
func makeNetwork(id: String, state: String = "running") -> ContainerNetwork {
    ContainerNetwork(
        id: id,
        state: state,
        config: NetworkConfig(labels: [:], id: id),
        status: NetworkStatus(gateway: nil, address: nil)
    )
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
    runner: MockCommandRunner = MockCommandRunner(),
    defaults: UserDefaults = ephemeralDefaults()
) -> ContainerService {
    ContainerService(backend: backend, runner: runner, defaults: defaults)
}

/// A throwaway `UserDefaults` suite, unique per call, so a service built in a test never
/// reads or mutates the real `.standard` domain (e.g. `safeContainerBinaryPath` clearing
/// a user's persisted binary path). Unused suites write nothing to disk.
func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "OrchardTests-\(UUID().uuidString)")!
}
