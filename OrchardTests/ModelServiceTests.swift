import Testing
import Foundation
@testable import Orchard

// ModelService detection + the network→bridge-environment resolution. Detection is
// best-effort and never alerts, so there is no error path to assert.

private func makeProvider(
    kind: ModelProvider.Kind = .mlxServer,
    host: String = ModelEndpoint.defaultHost,
    port: UInt16 = 8080,
    api: ModelAPIStyle = .openAI,
    models: [String] = ["llama-3.2-1b"],
    requiresAPIKey: Bool = false
) -> ModelProvider {
    ModelProvider(kind: kind, host: host, port: port, api: api, models: models, requiresAPIKey: requiresAPIKey)
}

private func makeNetwork(id: String = "default", gateway: String? = "192.168.66.1") -> ContainerNetwork {
    ContainerNetwork(
        id: id,
        state: "running",
        config: NetworkConfig(labels: [:], id: id),
        status: NetworkStatus(gateway: gateway, address: "192.168.66.0/24")
    )
}


@MainActor
private func makeSettings() -> SettingsStore {
    SettingsStore(alertCenter: AlertCenter(), defaults: ephemeralDefaults(), secrets: InMemorySecretsStore())
}

@MainActor
private func makeModelService(backend: ModelBackend) -> ModelService {
    ModelService(backend: backend, settings: makeSettings())
}

// MARK: - load

@Test("Models load: publishes detected providers and clears loading")
@MainActor
func modelsLoadSuccess() async {
    let backend = MockModelBackend(providers: [makeProvider()])
    let service = makeModelService(backend: backend)

    await service.load()

    #expect(service.providers.count == 1)
    #expect(service.providers.first?.models == ["llama-3.2-1b"])
    #expect(service.isLoading == false)
    #expect(backend.detectCount == 1)
}

@Test("Models load: no providers running publishes an empty list, not an error")
@MainActor
func modelsLoadEmpty() async {
    let service = makeModelService(backend: MockModelBackend(providers: []))

    await service.load()

    #expect(service.providers.isEmpty)
    #expect(service.isLoading == false)
}

// MARK: - bridgeEnvironment

@Test("Bridge env: resolves the network gateway into an OpenAI base URL")
@MainActor
func bridgeEnvResolvesGateway() {
    let service = makeModelService(backend: MockModelBackend())
    let env = service.bridgeEnvironment(for: makeProvider(port: 8080, api: .openAI), on: makeNetwork(gateway: "192.168.66.1"))

    #expect(env?.first { $0.key == "OPENAI_BASE_URL" }?.value == "http://192.168.66.1:8080/v1")
}

@Test("Bridge env: a network without a gateway yields nil (no route to host)")
@MainActor
func bridgeEnvNoGateway() {
    let service = makeModelService(backend: MockModelBackend())

    #expect(service.bridgeEnvironment(for: makeProvider(), on: makeNetwork(gateway: nil)) == nil)
    #expect(service.bridgeEnvironment(for: makeProvider(), on: makeNetwork(gateway: "")) == nil)
}

// MARK: - Refresh-tick backoff

@MainActor
@Test("refreshTick: with no providers, probes back off to the idle interval")
func refreshTickIdleBackoff() async {
    let backend = MockModelBackend()   // nothing listening
    let service = ModelService(
        backend: backend,
        settings: SettingsStore(alertCenter: AlertCenter(), defaults: ephemeralDefaults(), secrets: InMemorySecretsStore()),
        idleProbeInterval: 3600        // effectively "never again" within this test
    )

    await service.refreshTick()        // first tick probes (nothing probed yet)
    await service.refreshTick()        // inside the idle window: skipped
    await service.refreshTick()
    #expect(backend.detectCount == 1)
}

@MainActor
@Test("refreshTick: while a provider is detected, every tick probes")
func refreshTickActiveCadence() async {
    let backend = MockModelBackend(providers: [makeProvider()])
    let service = ModelService(
        backend: backend,
        settings: SettingsStore(alertCenter: AlertCenter(), defaults: ephemeralDefaults(), secrets: InMemorySecretsStore()),
        idleProbeInterval: 3600
    )

    await service.load(showLoading: false)   // discovers the provider
    await service.refreshTick()
    await service.refreshTick()
    #expect(backend.detectCount == 3)

    // The provider goes away: the next tick still probes (providers were
    // non-empty), notices the loss, and only then backs off.
    backend.providers = []
    await service.refreshTick()
    #expect(backend.detectCount == 4)
    #expect(service.providers.isEmpty)
    await service.refreshTick()
    #expect(backend.detectCount == 4)        // now idle: skipped
}

// MARK: - Endpoint configuration (#110)

@MainActor
@Test("Detect: probes the configured endpoints, seeded from the built-in defaults")
func detectUsesConfiguredEndpoints() async {
    let backend = MockModelBackend()
    let service = ModelService(backend: backend, settings: makeSettings())

    await service.load()

    #expect(backend.lastEndpoints.map(\.id) == ModelEndpoint.builtIns.map(\.id))
    #expect(service.endpoints.filter { !$0.isEnabled }.isEmpty)
}

@MainActor
@Test("Endpoints: disabling one persists and hands the backend an endpoint that is off")
func disableEndpointPersists() async {
    let defaults = ephemeralDefaults()
    let backend = MockModelBackend()
    let settings = SettingsStore(alertCenter: AlertCenter(), defaults: defaults, secrets: InMemorySecretsStore())
    let service = ModelService(backend: backend, settings: settings)

    await service.setEndpointEnabled(false, id: "builtin.lmstudio.1234")

    #expect(service.endpoints.first { $0.id == "builtin.lmstudio.1234" }?.isEnabled == false)
    #expect(backend.lastEndpoints.first { $0.id == "builtin.lmstudio.1234" }?.isEnabled == false)

    // A fresh store on the same suite reads the choice back: the off switch survives a
    // relaunch, which is the whole point of it.
    let reloaded = SettingsStore(alertCenter: AlertCenter(), defaults: defaults, secrets: InMemorySecretsStore())
    #expect(reloaded.modelEndpoints.first { $0.id == "builtin.lmstudio.1234" }?.isEnabled == false)
}

@MainActor
@Test("Endpoints: re-pointing one changes the probed address but keeps its identity")
func editEndpointAddress() async {
    let backend = MockModelBackend()
    let service = ModelService(backend: backend, settings: makeSettings())
    var endpoint = service.endpoints.first { $0.id == "builtin.lmstudio.1234" }!
    endpoint.host = "10.0.0.7"
    endpoint.port = 4321

    await service.updateEndpoint(endpoint)

    let probed = backend.lastEndpoints.first { $0.id == "builtin.lmstudio.1234" }
    #expect(probed?.host == "10.0.0.7")
    #expect(probed?.port == 4321)
    #expect(probed?.listPath == "/v1/models")

    await service.restoreDefaultEndpoint(id: "builtin.lmstudio.1234")
    let restored = service.endpoints.first { $0.id == "builtin.lmstudio.1234" }
    #expect(restored?.host == ModelEndpoint.defaultHost)
    #expect(restored?.port == 1234)
}

@MainActor
@Test("API keys: a saved key reaches the next probe, keyed by endpoint")
func savedKeyReachesProbe() async {
    let backend = MockModelBackend()
    let service = ModelService(backend: backend, settings: makeSettings())
    let endpoint = service.endpoints.first { $0.id == "builtin.mlx.8000" }!

    try? await service.setAPIKey("sk-live", host: endpoint.host, port: endpoint.port)

    #expect(backend.lastAPIKeys["builtin.mlx.8000"] == "sk-live")
    #expect(service.hasAPIKey(host: endpoint.host, port: endpoint.port))

    try? await service.setAPIKey("", host: endpoint.host, port: endpoint.port)
    #expect(backend.lastAPIKeys["builtin.mlx.8000"] == nil)
    #expect(service.hasAPIKey(host: endpoint.host, port: endpoint.port) == false)
}

@MainActor
@Test("refreshTick: a locked provider backs off instead of probing every tick")
func refreshTickLockedBacksOff() async {
    // The reported symptom: a 401 server kept `providers` non-empty, which kept the tick
    // at its fast cadence, which hammered that server for as long as Orchard ran (#110).
    let backend = MockModelBackend(providers: [makeProvider(requiresAPIKey: true)])
    let service = ModelService(backend: backend, settings: makeSettings(), idleProbeInterval: 3600)

    await service.load(showLoading: false)
    #expect(backend.detectCount == 1)
    await service.refreshTick()
    await service.refreshTick()
    #expect(backend.detectCount == 1)

    // One usable provider is enough to earn the fast cadence back.
    backend.providers = [makeProvider(), makeProvider(port: 8000, requiresAPIKey: true)]
    await service.load(showLoading: false)
    await service.refreshTick()
    #expect(backend.detectCount == 3)
}

@MainActor
@Test("Bridge env: an endpoint on another machine needs no gateway")
func bridgeEnvRemoteHost() {
    let service = makeModelService(backend: MockModelBackend())
    let remote = makeProvider(host: "10.0.0.7", port: 4321)

    #expect(service.containerBaseURL(for: remote, on: makeNetwork(gateway: nil)) == "http://10.0.0.7:4321/v1")
    #expect(service.bridgeEnvironment(for: remote, on: makeNetwork())?.first { $0.key == "OPENAI_BASE_URL" }?.value
            == "http://10.0.0.7:4321/v1")
}

@MainActor
@Test("refreshTick: an explicit load resets the idle window")
func refreshTickExplicitLoadWins() async {
    let backend = MockModelBackend()
    let service = ModelService(
        backend: backend,
        settings: SettingsStore(alertCenter: AlertCenter(), defaults: ephemeralDefaults(), secrets: InMemorySecretsStore()),
        idleProbeInterval: 3600
    )

    await service.refreshTick()
    #expect(backend.detectCount == 1)
    // Opening the Models tab (or the bridge picker) always probes.
    await service.load(showLoading: false)
    #expect(backend.detectCount == 2)
}
