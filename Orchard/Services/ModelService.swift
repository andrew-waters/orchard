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

    init(backend: ModelBackend) {
        self.backend = backend
    }

    func load(showLoading: Bool = true) async {
        if showLoading { isLoading = true }
        let providers = await backend.detectProviders()
        if providers != self.providers {
            self.providers = providers
        }
        self.isLoading = false
    }

    /// Send a chat conversation to a provider running on the host and return its reply.
    /// Surfaces transport/HTTP errors to the caller (the tester shows them inline).
    func complete(port: UInt16, api: ModelAPIStyle, model: String, messages: [ChatMessage]) async throws -> String {
        try await backend.complete(port: port, api: api, model: model, messages: messages)
    }

    /// The environment-variable pairs to inject so a container attached to `network`
    /// reaches `provider` on the host. Returns nil when the network has no usable gateway
    /// (the container would have no route to the host).
    func bridgeEnvironment(for provider: ModelProvider, on network: ContainerNetwork) -> [(key: String, value: String)]? {
        guard let gateway = network.status.gateway, !gateway.isEmpty else { return nil }
        let baseURL = ModelBridge.containerBaseURL(gateway: gateway, hostPort: provider.port, api: provider.api)
        return ModelBridge.injectionEnvironment(baseURL: baseURL, api: provider.api)
    }
}
