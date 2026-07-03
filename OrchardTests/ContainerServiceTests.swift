import Testing
import Foundation
@testable import Orchard

// MARK: - ContainerRunConfig → ContainerCreateSpec

@MainActor
@Test("Spec: valid ports are parsed to UInt16, invalid ones dropped")
func specPortParsing() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    var config = ContainerRunConfig(name: "web", image: "nginx")
    config.portMappings = [
        .init(hostPort: "8080", containerPort: "80"),
        .init(hostPort: "notaport", containerPort: "80"),
    ]
    await service.runContainer(config: config)

    let spec = backend.createdSpecs.first
    #expect(spec?.publishedPorts.count == 1)
    #expect(spec?.publishedPorts.first?.hostPort == 8080)
    #expect(spec?.publishedPorts.first?.containerPort == 80)
}

@MainActor
@Test("Spec: volumes with an empty path are dropped; readonly is carried through")
func specVolumeFiltering() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    var config = ContainerRunConfig(name: "web", image: "nginx")
    config.volumeMappings = [
        .init(hostPath: "/host", containerPath: "/data", readonly: true),
        .init(hostPath: "", containerPath: "/nope"),
    ]
    await service.runContainer(config: config)

    let spec = backend.createdSpecs.first
    #expect(spec?.volumes.count == 1)
    #expect(spec?.volumes.first?.hostPath == "/host")
    #expect(spec?.volumes.first?.readonly == true)
}

@MainActor
@Test("Spec: env vars join as KEY=VALUE and empty keys are dropped")
func specEnvJoining() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    var config = ContainerRunConfig(name: "web", image: "nginx")
    config.environmentVariables = [
        .init(key: "FOO", value: "bar"),
        .init(key: "", value: "ignored"),
    ]
    await service.runContainer(config: config)

    #expect(backend.createdSpecs.first?.environment == ["FOO=bar"])
}

@MainActor
@Test("Spec: command override is split on spaces; empty name generates an id")
func specCommandAndName() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    var config = ContainerRunConfig(name: "", image: "nginx")
    config.commandOverride = "sh -c echo"
    config.dnsDomain = "test"
    await service.runContainer(config: config)

    let spec = backend.createdSpecs.first
    #expect(spec?.commandOverride == ["sh", "-c", "echo"])
    #expect(spec?.dnsDomain == "test")
    #expect(spec?.id.isEmpty == false)   // empty name → generated id
}

// MARK: - Service state transitions

@MainActor
@Test("loadContainers failure surfaces an alert while the system is running")
func loadContainersFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.listContainersError = NotConfigured()
    let service = makeService(backend: backend)
    service.systemService.systemStatus = .running

    await service.loadContainers(showLoading: true)

    #expect(service.alertCenter.current != nil)
    #expect(service.isLoading == false)
}

@MainActor
@Test("loadContainers failure stays silent when the system is not running")
func loadContainersFailureSilentWhenStopped() async {
    let backend = MockContainerBackend()
    backend.listContainersError = NotConfigured()
    let service = makeService(backend: backend)
    service.systemService.systemStatus = .stopped

    await service.loadContainers(showLoading: true)

    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("loadBuilders: 'not running' output clears builders and sets .stopped")
func loadBuildersNotRunning() async {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(exitCode: 0, stdout: "builder is not running", stderr: nil)
    let service = makeService(runner: runner)

    await service.loadBuilders()

    #expect(service.builders.isEmpty)
    #expect(service.builderStatus == .stopped)
}

@MainActor
@Test("startContainer retries transition errors then surfaces a failure alert")
func startRetryExhausted() async {
    let backend = MockContainerBackend()
    backend.bootstrapAndStartHandler = { _ in
        throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalidState"])
    }
    let service = makeService(backend: backend)

    await service.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 3)
    #expect(service.alertCenter.current?.message.contains("failed to start") == true)
    #expect(service.loadingContainers.contains("web") == false)
}

@MainActor
@Test("startContainer succeeds on the first attempt with no alert")
func startSucceedsFirstTry() async {
    let backend = MockContainerBackend()   // no handler → bootstrapAndStart succeeds
    let service = makeService(backend: backend)

    await service.startContainer("web", maxRetries: 3, retryDelay: 0)

    #expect(backend.bootstrapAndStartCount == 1)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("Stats: an alert appears only when every running container fails")
func statsAllFailAlerts() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { _ in throw NotConfigured() }   // all fail
    let service = makeService(backend: backend)
    service.systemService.systemStatus = .running
    service.containers = [try makeContainer(id: "a", status: "running")]

    await service.loadContainerStats(showLoading: true)

    #expect(service.alertCenter.current != nil)
    #expect(service.containerStats.isEmpty)
}

@MainActor
@Test("Stats: one failing container among several does not raise an alert")
func statsPartialFailureIsSilent() async throws {
    let backend = MockContainerBackend()
    backend.statsHandler = { id in
        if id == "a" { return makeStats(id: id) }
        throw NotConfigured()
    }
    let service = makeService(backend: backend)
    service.systemService.systemStatus = .running
    service.containers = [
        try makeContainer(id: "a", status: "running"),
        try makeContainer(id: "b", status: "running"),
    ]

    await service.loadContainerStats(showLoading: true)

    #expect(service.alertCenter.current == nil)
    #expect(service.containerStats.count == 1)
}
