import Foundation

/// Owns discovered local-model providers and bridges them to containers. Read-only in this
/// first slice: detect providers on the refresh tick and expose them for the
/// container-create bridge. Follows the per-domain service template - `@Published` state
/// and a `load()` the refresh loop calls. Detection never alerts: a missing provider is a
/// normal, expected state, not an error.
@MainActor
final class ModelService: ObservableObject {
    @Published var providers: [ModelProvider] = []
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
    }

    func load(showLoading: Bool = true) async {
        if showLoading { isLoading = true }
        lastProbeAt = Date()
        let providers = await backend.detectProviders(apiKeys: settings.allModelAPIKeys())
        if providers != self.providers {
            self.providers = providers
        }
        self.isLoading = false
    }

    /// Detection for the shared refresh timer. While providers exist, every
    /// tick probes so a stopped server disappears promptly; while none do,
    /// probing four ports every 5s just sprays connection-refused errors into
    /// the console (CFNetwork logs each failed task), so the tick backs off to
    /// `idleProbeInterval`. Surfaces that need fresh results now - the Models
    /// tab, the run form's model bridge - call `load()` directly.
    func refreshTick() async {
        if providers.isEmpty, Date().timeIntervalSince(lastProbeAt) < idleProbeInterval {
            return
        }
        await load(showLoading: false)
    }

    /// Send a chat conversation to a provider running on the host and return its reply.
    /// Surfaces transport/HTTP errors to the caller (the tester shows them inline).
    func complete(port: UInt16, api: ModelAPIStyle, model: String, messages: [ChatMessage]) async throws -> String {
        try await backend.complete(port: port, api: api, model: model, messages: messages, apiKey: settings.modelAPIKey(port: port))
    }

    /// Store (or clear, when empty) the API key for the server on `port`, then re-detect
    /// so a locked provider unlocks immediately.
    func setAPIKey(_ key: String, port: UInt16) async {
        settings.setModelAPIKey(key, port: port)
        await load(showLoading: false)
    }

    /// The environment-variable pairs to inject so a container attached to `network`
    /// reaches `provider` on the host. Returns nil when the network has no usable gateway
    /// (the container would have no route to the host).
    func bridgeEnvironment(for provider: ModelProvider, on network: ContainerNetwork) -> [(key: String, value: String)]? {
        guard let gateway = network.status.gateway, !gateway.isEmpty else { return nil }
        let baseURL = ModelBridge.containerBaseURL(gateway: gateway, hostPort: provider.port, api: provider.api)
        return ModelBridge.injectionEnvironment(baseURL: baseURL, api: provider.api, apiKey: settings.modelAPIKey(port: provider.port))
    }
}
