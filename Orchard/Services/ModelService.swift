import Foundation

/// Owns the local-model endpoints Orchard probes, the providers that answered, and the
/// bridge from those providers into containers. Detection runs on the refresh tick; the
/// endpoint list is user-owned, so re-pointing, disabling and API keys all come through
/// here and re-detect on the spot. Follows the per-domain service template - `@Published`
/// state and a `load()` the refresh loop calls. Detection never alerts: a missing provider
/// is a normal, expected state, not an error. Configuration does alert, via a thrown
/// error, because a credential that failed to save is not a normal state.
@MainActor
final class ModelService: ObservableObject {
    @Published var providers: [ModelProvider] = []
    /// The configured probe list, in list order. Mirrored from settings rather than read
    /// through it so the panel binds to one observable object for both halves: the
    /// detected providers and the endpoints that produced them.
    @Published private(set) var endpoints: [ModelEndpoint] = []
    @Published var isLoading = false

    private let backend: ModelBackend
    private let settings: SettingsStore
    /// Minimum gap between background probes while no provider is detected.
    private let idleProbeInterval: TimeInterval
    private var lastProbeAt: Date = .distantPast

    init(backend: ModelBackend, settings: SettingsStore, idleProbeInterval: TimeInterval = 30) {
        self.backend = backend
        self.settings = settings
        self.idleProbeInterval = idleProbeInterval
        self.endpoints = settings.modelEndpoints
    }

    func load(showLoading: Bool = true) async {
        if showLoading { isLoading = true }
        lastProbeAt = Date()
        let configured = settings.modelEndpoints
        endpoints = configured
        let providers = await backend.detectProviders(
            endpoints: configured,
            apiKeys: settings.modelAPIKeys(for: configured))
        if providers != self.providers {
            self.providers = providers
        }
        self.isLoading = false
    }

    /// Detection for the shared refresh timer. While a usable provider exists, every tick
    /// probes so a stopped server disappears promptly; otherwise the tick backs off to
    /// `idleProbeInterval`. "Otherwise" covers two cases. With nothing detected, probing
    /// every port every 5s just sprays connection-refused errors into the console
    /// (CFNetwork logs each failed task). With only locked providers detected, the fast
    /// cadence is worse than useless: the probe can't get anywhere without a key, so it
    /// spends the session hammering someone else's server with requests it knows will be
    /// rejected, which is exactly what #110 reported. A key saved through `setAPIKey`
    /// re-probes immediately, so backing off costs no responsiveness where it matters.
    /// Surfaces that need fresh results now - the Models tab, the run form's model
    /// bridge - call `load()` directly.
    func refreshTick() async {
        if !hasUnlockedProvider, Date().timeIntervalSince(lastProbeAt) < idleProbeInterval {
            return
        }
        await load(showLoading: false)
    }

    /// Whether anything detected is actually usable, as opposed to running but locked.
    private var hasUnlockedProvider: Bool {
        providers.contains { !$0.requiresAPIKey }
    }

    /// Send a chat conversation to a provider running on the host and return its reply.
    /// Surfaces transport/HTTP errors to the caller (the tester shows them inline).
    func complete(host: String = ModelEndpoint.defaultHost, port: UInt16, api: ModelAPIStyle, model: String, messages: [ChatMessage]) async throws -> String {
        try await backend.complete(
            host: host,
            port: port,
            api: api,
            model: model,
            messages: messages,
            apiKey: settings.modelAPIKey(host: host, port: port))
    }

    /// Store (or clear, when empty) the API key for the server on `host:port`, then
    /// re-detect so a locked provider unlocks immediately. Throws the keychain's refusal
    /// straight through: the caller shows it, because "nothing visibly happened" is the
    /// one outcome that leaves a user with nowhere to go (#110).
    func setAPIKey(_ key: String, host: String = ModelEndpoint.defaultHost, port: UInt16) async throws {
        try settings.setModelAPIKey(key, host: host, port: port)
        await load(showLoading: false)
    }

    /// Whether a key is already stored for this address. The panel needs this because an
    /// empty secure field means either "no key" or "a key you can't see", and those are
    /// very different things to be looking at.
    func hasAPIKey(host: String, port: UInt16) -> Bool {
        settings.modelAPIKey(host: host, port: port) != nil
    }

    // MARK: - Endpoint configuration

    /// Re-point an endpoint. Re-detects immediately so the panel reflects the new address
    /// without waiting on a tick.
    func updateEndpoint(_ endpoint: ModelEndpoint) async {
        settings.updateModelEndpoint(endpoint)
        await load(showLoading: false)
    }

    /// Switch an endpoint on or off. Disabling drops its provider from the list on the
    /// next detect, and stops it being probed at all from here on.
    func setEndpointEnabled(_ enabled: Bool, id: String) async {
        settings.setModelEndpointEnabled(enabled, id: id)
        await load(showLoading: false)
    }

    func restoreDefaultEndpoint(id: String) async {
        settings.restoreDefaultModelEndpoint(id: id)
        await load(showLoading: false)
    }

    /// The environment-variable pairs to inject so a container attached to `network`
    /// reaches `provider` on the host. Returns nil when the network has no usable gateway
    /// (the container would have no route to the host).
    func bridgeEnvironment(for provider: ModelProvider, on network: ContainerNetwork) -> [(key: String, value: String)]? {
        guard let baseURL = containerBaseURL(for: provider, on: network) else { return nil }
        return ModelBridge.injectionEnvironment(
            baseURL: baseURL,
            api: provider.api,
            apiKey: settings.modelAPIKey(host: provider.host, port: provider.port))
    }

    /// The address a container on `network` uses to reach `provider`, or nil when the
    /// network has no gateway and the provider is on this Mac. A provider the user has
    /// pointed at another machine needs no gateway, so it resolves either way.
    func containerBaseURL(for provider: ModelProvider, on network: ContainerNetwork) -> String? {
        let gateway = network.status.gateway ?? ""
        guard !gateway.isEmpty || !provider.isLoopback else { return nil }
        return ModelBridge.containerBaseURL(
            gateway: gateway,
            host: provider.host,
            hostPort: provider.port,
            api: provider.api)
    }
}
