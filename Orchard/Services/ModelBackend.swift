import Foundation

// MARK: - The container↔model bridge (pure)

/// Computes how a container reaches a model server running on the host, and the
/// environment a container needs to talk to it. Pure and package-free so it unit-tests in
/// isolation.
///
/// Load-bearing fact, verified against `container` 1.1.0: a workload's default route is
/// its network's vmnet gateway, and the host is reachable at that gateway address — *if*
/// the server binds all interfaces (`0.0.0.0`). A loopback-only (`127.0.0.1`) server is
/// refused from inside a container. So the bridge address is the network gateway, and it
/// is the provider's responsibility to actually listen on `0.0.0.0`.
enum ModelBridge {
    /// The base URL a container on a network with `gateway` uses to reach a host provider
    /// on `hostPort`. `gateway` is `ContainerNetwork.status.gateway` (the vmnet gateway,
    /// which is the host). OpenAI-style clients expect the `/v1` root; Ollama clients want
    /// the bare host.
    static func containerBaseURL(gateway: String, hostPort: UInt16, api: ModelAPIStyle) -> String {
        let root = "http://\(gateway):\(hostPort)"
        switch api {
        case .openAI: return root + "/v1"
        case .ollama: return root
        }
    }

    /// Environment variables (as `key`/`value` pairs) to inject into a container so a
    /// standard client inside it reaches the host provider at `baseURL`. The placeholder
    /// key satisfies SDKs that require one even though a local server ignores it.
    static func injectionEnvironment(baseURL: String, api: ModelAPIStyle) -> [(key: String, value: String)] {
        switch api {
        case .openAI:
            return [
                ("OPENAI_BASE_URL", baseURL),
                ("OPENAI_API_KEY", "not-needed"),
            ]
        case .ollama:
            return [
                ("OLLAMA_HOST", baseURL),
            ]
        }
    }
}

// MARK: - Backend protocol

/// The local-model discovery surface. Read-only in this slice: detect providers running on
/// the host and list the models they advertise. Mirrors `ContainerBackend`'s rule —
/// app-owned types only, so mocks need no package imports.
protocol ModelBackend: Sendable {
    /// Probe the host for running model providers and return those that responded.
    /// Best-effort: never throws, since a missing provider is a normal state.
    func detectProviders() async -> [ModelProvider]
}

// MARK: - Live implementation

/// `ModelBackend` that discovers providers by probing their conventional loopback ports
/// over HTTP. An unreachable port simply means "that provider isn't running."
struct LiveModelBackend: ModelBackend {
    /// One provider Orchard knows how to detect: its conventional port and the listing
    /// endpoint used both to confirm liveness and to enumerate models.
    struct Candidate: Sendable {
        let kind: ModelProvider.Kind
        let port: UInt16
        let api: ModelAPIStyle
        let listPath: String
    }

    /// ⚠ Ports are conventional defaults — revisit if they prove unreliable in the field.
    static let candidates: [Candidate] = [
        Candidate(kind: .ollama, port: 11434, api: .ollama, listPath: "/api/tags"),
        Candidate(kind: .lmStudio, port: 1234, api: .openAI, listPath: "/v1/models"),
        Candidate(kind: .mlxServer, port: 8080, api: .openAI, listPath: "/v1/models"),
        Candidate(kind: .mlxServer, port: 8000, api: .openAI, listPath: "/v1/models"),
    ]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func detectProviders() async -> [ModelProvider] {
        let session = self.session
        return await withTaskGroup(of: ModelProvider?.self) { group in
            for candidate in Self.candidates {
                group.addTask { await Self.probe(candidate, session: session) }
            }
            var found: [ModelProvider] = []
            for await result in group {
                if let result { found.append(result) }
            }
            return found.sorted { $0.id < $1.id }
        }
    }

    private static func probe(_ candidate: Candidate, session: URLSession) async -> ModelProvider? {
        guard let url = URL(string: "http://127.0.0.1:\(candidate.port)\(candidate.listPath)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return ModelProvider(
            kind: candidate.kind,
            port: candidate.port,
            api: candidate.api,
            models: parseModels(data, api: candidate.api)
        )
    }

    /// Extract model ids from a provider's listing response. Both shapes are flat JSON.
    static func parseModels(_ data: Data, api: ModelAPIStyle) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        switch api {
        case .openAI:
            // { "data": [ { "id": "..." }, ... ] }
            let arr = obj["data"] as? [[String: Any]] ?? []
            return arr.compactMap { $0["id"] as? String }
        case .ollama:
            // { "models": [ { "name": "..." }, ... ] }
            let arr = obj["models"] as? [[String: Any]] ?? []
            return arr.compactMap { $0["name"] as? String }
        }
    }
}
