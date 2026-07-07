import Foundation
@testable import Orchard

struct NotConfigured: Error {}

/// An error carrying `message` as its `localizedDescription` — for driving classified
/// error paths (e.g. OrchardError.classifyStartError matches on the message text).
func makeError(_ message: String) -> NSError {
    NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

// The mocks are `@unchecked Sendable` and their methods run off the main actor (nonisolated
// async protocol requirements), so fire-and-forget service Tasks can touch their state
// concurrently. All mutable state is therefore guarded by an `NSLock` — config via get/set
// accessors, recorded calls/counters via a locked mutation inside each method with a
// get-only accessor for tests. Recorded arrays append on SUCCESS only (throw first), so a
// failed operation never looks like it happened.

/// Records issued commands and lets tests supply canned CLI output.
final class MockCommandRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _defaultResult = ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    private var _runHandler: (@Sendable (String, [String]) throws -> ProcessResult)?
    private var _calls: [[String]] = []

    var defaultResult: ProcessResult {
        get { lock.withLock { _defaultResult } }
        set { lock.withLock { _defaultResult = newValue } }
    }
    var runHandler: (@Sendable (String, [String]) throws -> ProcessResult)? {
        get { lock.withLock { _runHandler } }
        set { lock.withLock { _runHandler = newValue } }
    }
    var calls: [[String]] { lock.withLock { _calls } }

    func run(program: String, arguments: [String]) async throws -> ProcessResult {
        lock.withLock { _calls.append(arguments) }
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
    private let lock = NSLock()

    private var _containers: [Container] = []
    private var _images: [ContainerImage] = []
    private var _networks: [ContainerNetwork] = []
    private var _listContainersError: Error?
    private var _listImagesError: Error?
    private var _pullImageError: Error?
    private var _deleteImageError: Error?
    private var _listNetworksError: Error?
    private var _createNetworkError: Error?
    private var _deleteNetworkError: Error?
    private var _createContainerError: Error?
    private var _stopContainerError: Error?
    private var _killContainerError: Error?
    private var _deleteContainerError: Error?
    private var _pingError: Error?
    private var _bootstrapAndStartHandler: (@Sendable (Int) throws -> Void)?
    private var _statsHandler: (@Sendable (String) throws -> Orchard.ContainerStats)?

    private var _pulledReferences: [String] = []
    private var _deletedImageReferences: [String] = []
    private var _createdNetworks: [(name: String, subnet: String?, labels: [String: String])] = []
    private var _deletedNetworkIds: [String] = []
    private var _createdSpecs: [ContainerCreateSpec] = []
    private var _deletedContainers: [(id: String, force: Bool)] = []
    private var _bootstrapAndStartCount = 0
    private var _listContainersCount = 0

    // Configuration — set by tests.
    var containers: [Container] {
        get { lock.withLock { _containers } }
        set { lock.withLock { _containers = newValue } }
    }
    var images: [ContainerImage] {
        get { lock.withLock { _images } }
        set { lock.withLock { _images = newValue } }
    }
    var networks: [ContainerNetwork] {
        get { lock.withLock { _networks } }
        set { lock.withLock { _networks = newValue } }
    }
    var listContainersError: Error? {
        get { lock.withLock { _listContainersError } }
        set { lock.withLock { _listContainersError = newValue } }
    }
    var listImagesError: Error? {
        get { lock.withLock { _listImagesError } }
        set { lock.withLock { _listImagesError = newValue } }
    }
    var pullImageError: Error? {
        get { lock.withLock { _pullImageError } }
        set { lock.withLock { _pullImageError = newValue } }
    }
    var deleteImageError: Error? {
        get { lock.withLock { _deleteImageError } }
        set { lock.withLock { _deleteImageError = newValue } }
    }
    var listNetworksError: Error? {
        get { lock.withLock { _listNetworksError } }
        set { lock.withLock { _listNetworksError = newValue } }
    }
    var createNetworkError: Error? {
        get { lock.withLock { _createNetworkError } }
        set { lock.withLock { _createNetworkError = newValue } }
    }
    var deleteNetworkError: Error? {
        get { lock.withLock { _deleteNetworkError } }
        set { lock.withLock { _deleteNetworkError = newValue } }
    }
    var createContainerError: Error? {
        get { lock.withLock { _createContainerError } }
        set { lock.withLock { _createContainerError = newValue } }
    }
    var stopContainerError: Error? {
        get { lock.withLock { _stopContainerError } }
        set { lock.withLock { _stopContainerError = newValue } }
    }
    var killContainerError: Error? {
        get { lock.withLock { _killContainerError } }
        set { lock.withLock { _killContainerError = newValue } }
    }
    var deleteContainerError: Error? {
        get { lock.withLock { _deleteContainerError } }
        set { lock.withLock { _deleteContainerError = newValue } }
    }
    var pingError: Error? {
        get { lock.withLock { _pingError } }
        set { lock.withLock { _pingError = newValue } }
    }
    /// Called with the 1-based attempt count; throw to simulate a failed start.
    var bootstrapAndStartHandler: (@Sendable (Int) throws -> Void)? {
        get { lock.withLock { _bootstrapAndStartHandler } }
        set { lock.withLock { _bootstrapAndStartHandler = newValue } }
    }
    /// Per-container stats; throw to simulate a failure for that container.
    var statsHandler: (@Sendable (String) throws -> Orchard.ContainerStats)? {
        get { lock.withLock { _statsHandler } }
        set { lock.withLock { _statsHandler = newValue } }
    }

    // Recorded calls — read by tests.
    var pulledReferences: [String] { lock.withLock { _pulledReferences } }
    var deletedImageReferences: [String] { lock.withLock { _deletedImageReferences } }
    var createdNetworks: [(name: String, subnet: String?, labels: [String: String])] { lock.withLock { _createdNetworks } }
    var deletedNetworkIds: [String] { lock.withLock { _deletedNetworkIds } }
    var createdSpecs: [ContainerCreateSpec] { lock.withLock { _createdSpecs } }
    var deletedContainers: [(id: String, force: Bool)] { lock.withLock { _deletedContainers } }
    var bootstrapAndStartCount: Int { lock.withLock { _bootstrapAndStartCount } }
    var listContainersCount: Int { lock.withLock { _listContainersCount } }

    func listContainers() async throws -> [Container] {
        lock.withLock { _listContainersCount += 1 }
        if let error = listContainersError { throw error }
        return containers
    }
    func stopContainer(id: String) async throws {
        if let stopContainerError { throw stopContainerError }
    }
    func killContainer(id: String, signal: Int32) async throws {
        if let killContainerError { throw killContainerError }
    }
    func deleteContainer(id: String, force: Bool) async throws {
        if let deleteContainerError { throw deleteContainerError }
        lock.withLock { _deletedContainers.append((id: id, force: force)) }
    }
    func bootstrapAndStart(id: String) async throws {
        // Counts every attempt (including failed ones) — increment before the handler throws.
        let attempt = lock.withLock { () -> Int in _bootstrapAndStartCount += 1; return _bootstrapAndStartCount }
        try bootstrapAndStartHandler?(attempt)
    }
    func containerLogs(id: String) async throws -> [FileHandle] { [] }
    func stats(id: String) async throws -> Orchard.ContainerStats {
        if let handler = statsHandler { return try handler(id) }
        throw NotConfigured()
    }
    func createContainer(_ spec: ContainerCreateSpec) async throws {
        if let error = createContainerError { throw error }
        lock.withLock { _createdSpecs.append(spec) }
    }
    func listImages() async throws -> [ContainerImage] {
        if let listImagesError { throw listImagesError }
        return images
    }
    func pullImage(reference: String) async throws {
        if let pullImageError { throw pullImageError }
        lock.withLock { _pulledReferences.append(reference) }
    }
    func deleteImage(reference: String) async throws {
        if let deleteImageError { throw deleteImageError }
        lock.withLock { _deletedImageReferences.append(reference) }
    }
    func inspectImage(reference: String) async throws -> ImageInspection { throw NotConfigured() }
    func listNetworks() async throws -> [ContainerNetwork] {
        if let listNetworksError { throw listNetworksError }
        return networks
    }
    func createNetwork(name: String, subnet: String?, labels: [String: String]) async throws {
        if let createNetworkError { throw createNetworkError }
        lock.withLock { _createdNetworks.append((name: name, subnet: subnet, labels: labels)) }
    }
    func deleteNetwork(id: String) async throws {
        if let deleteNetworkError { throw deleteNetworkError }
        lock.withLock { _deletedNetworkIds.append(id) }
    }
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
) -> AppServices {
    AppServices(backend: backend, runner: runner, defaults: defaults)
}

/// A throwaway `UserDefaults` suite, unique per call, so a service built in a test never
/// reads or mutates the real `.standard` domain (e.g. `safeContainerBinaryPath` clearing
/// a user's persisted binary path). Unused suites write nothing to disk.
func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "OrchardTests-\(UUID().uuidString)")!
}

// MARK: - Machine mocks

extension Machine {
    /// Test-only copy with selected fields overridden. Used by `MockMachineBackend` to model
    /// lifecycle transitions and by tests to build fixtures without repeating every field.
    func copy(status: String? = nil, isDefault: Bool? = nil) -> Machine {
        Machine(
            id: id,
            status: status ?? self.status,
            isDefault: isDefault ?? self.isDefault,
            cpus: cpus,
            memoryBytes: memoryBytes,
            diskSizeBytes: diskSizeBytes,
            homeMount: homeMount,
            virtualization: virtualization,
            kernelPath: kernelPath,
            imageReference: imageReference,
            platform: platform,
            ipAddress: ipAddress,
            containerId: containerId,
            createdDate: createdDate,
            startedDate: startedDate,
            initialized: initialized,
            userSetup: userSetup
        )
    }
}

/// Build a `Machine` for tests. Defaults mirror the M0 alpine capture (4cpu/4G, rw home).
func makeMachine(
    id: String,
    status: String = "running",
    isDefault: Bool = false,
    ipAddress: String? = "192.168.66.7"
) -> Machine {
    Machine(
        id: id,
        status: status,
        isDefault: isDefault,
        cpus: 4,
        memoryBytes: 4_294_967_296,
        diskSizeBytes: 78_659_584,
        homeMount: "rw",
        virtualization: false,
        kernelPath: nil,
        imageReference: "docker.io/library/alpine:3.22",
        platform: Platform(os: "linux", architecture: "arm64", variant: nil),
        ipAddress: status == "running" ? ipAddress : nil,
        containerId: status == "running" ? "\(id)-13ab40" : nil,
        createdDate: Date(timeIntervalSince1970: 1_751_888_675),
        startedDate: status == "running" ? Date(timeIntervalSince1970: 1_751_888_677) : nil,
        initialized: true,
        userSetup: MachineUserSetup(username: "aw", uid: 501, gid: 20)
    )
}

/// A `MachineBackend` whose behaviour is configured per test. Lifecycle calls mutate the
/// stored machines (boot→running, stop→stopped, delete→removed, setDefault→flips the badge)
/// so a subsequent `listMachines()` reflects the transition, matching the live daemon.
final class MockMachineBackend: MachineBackend, @unchecked Sendable {
    private let lock = NSLock()

    private var _machines: [Machine] = []
    private var _listError: Error?
    private var _bootError: Error?
    private var _stopError: Error?
    private var _deleteError: Error?
    private var _setDefaultError: Error?
    private var _logsError: Error?
    private var _logs: [FileHandle] = []

    private var _bootedIds: [String] = []
    private var _stoppedIds: [String] = []
    private var _deletedIds: [String] = []
    private var _setDefaultIds: [String] = []
    private var _createdSpecs: [MachineCreateSpec] = []
    private var _createError: Error?
    private var _setConfigCalls: [(id: String, config: MachineConfigSpec)] = []
    private var _setConfigError: Error?

    var machines: [Machine] {
        get { lock.withLock { _machines } }
        set { lock.withLock { _machines = newValue } }
    }
    var listError: Error? {
        get { lock.withLock { _listError } }
        set { lock.withLock { _listError = newValue } }
    }
    var bootError: Error? {
        get { lock.withLock { _bootError } }
        set { lock.withLock { _bootError = newValue } }
    }
    var stopError: Error? {
        get { lock.withLock { _stopError } }
        set { lock.withLock { _stopError = newValue } }
    }
    var deleteError: Error? {
        get { lock.withLock { _deleteError } }
        set { lock.withLock { _deleteError = newValue } }
    }
    var setDefaultError: Error? {
        get { lock.withLock { _setDefaultError } }
        set { lock.withLock { _setDefaultError = newValue } }
    }
    var logsError: Error? {
        get { lock.withLock { _logsError } }
        set { lock.withLock { _logsError = newValue } }
    }
    var logs: [FileHandle] {
        get { lock.withLock { _logs } }
        set { lock.withLock { _logs = newValue } }
    }

    var createError: Error? {
        get { lock.withLock { _createError } }
        set { lock.withLock { _createError = newValue } }
    }
    var setConfigError: Error? {
        get { lock.withLock { _setConfigError } }
        set { lock.withLock { _setConfigError = newValue } }
    }

    var bootedIds: [String] { lock.withLock { _bootedIds } }
    var setConfigCalls: [(id: String, config: MachineConfigSpec)] { lock.withLock { _setConfigCalls } }
    var stoppedIds: [String] { lock.withLock { _stoppedIds } }
    var deletedIds: [String] { lock.withLock { _deletedIds } }
    var setDefaultIds: [String] { lock.withLock { _setDefaultIds } }
    var createdSpecs: [MachineCreateSpec] { lock.withLock { _createdSpecs } }

    func listMachines() async throws -> [Machine] {
        if let error = listError { throw error }
        return machines
    }

    func inspectMachine(id: String) async throws -> Machine {
        if let error = listError { throw error }
        guard let machine = machines.first(where: { $0.id == id }) else {
            throw OrchardError.generic("machine \(id) not found")
        }
        return machine
    }

    func createMachine(_ spec: MachineCreateSpec) async throws {
        if let error = createError { throw error }
        lock.withLock {
            _createdSpecs.append(spec)
            _machines.append(makeMachine(id: spec.name, status: spec.noBoot ? "stopped" : "running", isDefault: spec.setDefault))
        }
    }

    func setMachineConfig(id: String, config: MachineConfigSpec) async throws {
        if let error = setConfigError { throw error }
        lock.withLock { _setConfigCalls.append((id: id, config: config)) }
    }

    func bootMachine(id: String) async throws {
        if let error = bootError { throw error }
        lock.withLock {
            _bootedIds.append(id)
            _machines = _machines.map { $0.id == id ? $0.copy(status: "running") : $0 }
        }
    }

    func stopMachine(id: String) async throws {
        if let error = stopError { throw error }
        lock.withLock {
            _stoppedIds.append(id)
            _machines = _machines.map { $0.id == id ? $0.copy(status: "stopped") : $0 }
        }
    }

    func deleteMachine(id: String) async throws {
        if let error = deleteError { throw error }
        lock.withLock {
            _deletedIds.append(id)
            _machines.removeAll { $0.id == id }
        }
    }

    func setDefaultMachine(id: String) async throws {
        if let error = setDefaultError { throw error }
        lock.withLock {
            _setDefaultIds.append(id)
            _machines = _machines.map { $0.copy(isDefault: $0.id == id) }
        }
    }

    func machineLogs(id: String) async throws -> [FileHandle] {
        if let error = logsError { throw error }
        return logs
    }
}
