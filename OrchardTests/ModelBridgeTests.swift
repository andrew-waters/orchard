import Testing
import Foundation
@testable import Orchard

// The container↔model bridge: pure endpoint computation, env-var injection, and the
// provider-listing JSON parsing. No I/O, so these assert exact strings.

// MARK: - containerBaseURL

@Test("Bridge URL: OpenAI-style appends /v1 to the gateway host")
func bridgeURLOpenAI() {
    let url = ModelBridge.containerBaseURL(gateway: "192.168.66.1", hostPort: 8080, api: .openAI)
    #expect(url == "http://192.168.66.1:8080/v1")
}

@Test("Bridge URL: Ollama-style uses the bare gateway host")
func bridgeURLOllama() {
    let url = ModelBridge.containerBaseURL(gateway: "192.168.66.1", hostPort: 11434, api: .ollama)
    #expect(url == "http://192.168.66.1:11434")
}

// MARK: - injectionEnvironment

@Test("Injection: OpenAI provider yields base URL plus a placeholder key")
func injectOpenAI() {
    let env = ModelBridge.injectionEnvironment(baseURL: "http://192.168.66.1:8080/v1", api: .openAI)
    #expect(env.count == 2)
    #expect(env.first { $0.key == "OPENAI_BASE_URL" }?.value == "http://192.168.66.1:8080/v1")
    #expect(env.first { $0.key == "OPENAI_API_KEY" }?.value == "not-needed")
}

@Test("Injection: Ollama provider yields OLLAMA_HOST only")
func injectOllama() {
    let env = ModelBridge.injectionEnvironment(baseURL: "http://192.168.66.1:11434", api: .ollama)
    #expect(env.map(\.key) == ["OLLAMA_HOST"])
    #expect(env.first?.value == "http://192.168.66.1:11434")
}

// MARK: - parseModels

@Test("Parse: OpenAI /v1/models response yields the model ids")
func parseOpenAIModels() {
    let json = Data(#"{"object":"list","data":[{"id":"llama-3.2-1b"},{"id":"qwen-0.5b"}]}"#.utf8)
    #expect(LiveModelBackend.parseModels(json, api: .openAI) == ["llama-3.2-1b", "qwen-0.5b"])
}

@Test("Parse: Ollama /api/tags response yields the model names")
func parseOllamaModels() {
    let json = Data(#"{"models":[{"name":"llama3.1:latest"},{"name":"mistral:7b"}]}"#.utf8)
    #expect(LiveModelBackend.parseModels(json, api: .ollama) == ["llama3.1:latest", "mistral:7b"])
}

@Test("Refine: an oMLX models listing (owned_by \"omlx\") reclassifies the provider")
func refineKindOMLX() {
    let json = Data(#"{"object":"list","data":[{"id":"llama-3.2-1b","owned_by":"omlx"}]}"#.utf8)
    #expect(LiveModelBackend.refineKind(.mlxServer, data: json, api: .openAI) == .omlx)
}

@Test("Refine: other owned_by values and non-OpenAI APIs keep the candidate's kind")
func refineKindPassthrough() {
    let mlx = Data(#"{"object":"list","data":[{"id":"llama-3.2-1b","owned_by":"mlx"}]}"#.utf8)
    #expect(LiveModelBackend.refineKind(.mlxServer, data: mlx, api: .openAI) == .mlxServer)

    let noOwner = Data(#"{"object":"list","data":[{"id":"llama-3.2-1b"}]}"#.utf8)
    #expect(LiveModelBackend.refineKind(.lmStudio, data: noOwner, api: .openAI) == .lmStudio)

    let ollama = Data(#"{"models":[{"name":"llama3.1:latest"}]}"#.utf8)
    #expect(LiveModelBackend.refineKind(.ollama, data: ollama, api: .ollama) == .ollama)

    #expect(LiveModelBackend.refineKind(.mlxServer, data: Data("not json".utf8), api: .openAI) == .mlxServer)
}

@Test("Parse: malformed or empty JSON yields no models rather than throwing")
func parseGarbage() {
    #expect(LiveModelBackend.parseModels(Data("not json".utf8), api: .openAI).isEmpty)
    #expect(LiveModelBackend.parseModels(Data("{}".utf8), api: .ollama).isEmpty)
}

// MARK: - parseCompletion

@Test("Completion parse: OpenAI response yields the assistant message content")
func parseCompletionOpenAI() throws {
    let json = Data(#"{"choices":[{"message":{"role":"assistant","content":"hello there"}}]}"#.utf8)
    #expect(try LiveModelBackend.parseCompletion(json, api: .openAI) == "hello there")
}

@Test("Completion parse: Ollama response yields the message content")
func parseCompletionOllama() throws {
    let json = Data(#"{"message":{"role":"assistant","content":"hi from ollama"}}"#.utf8)
    #expect(try LiveModelBackend.parseCompletion(json, api: .ollama) == "hi from ollama")
}

@Test("Completion parse: an unexpected shape throws rather than returning empty")
func parseCompletionBadShape() {
    #expect(throws: (any Error).self) {
        try LiveModelBackend.parseCompletion(Data("{}".utf8), api: .openAI)
    }
}

// MARK: - Probe classification and API keys (#72 follow-up)

private let omlxEndpoint = ModelEndpoint(id: "test.omlx", kind: .mlxServer, port: 8000, api: .openAI)

@Test("Probe: a 200 with an oMLX listing yields an unlocked oMLX provider")
func probeClassifiesOK() {
    let json = Data(#"{"object":"list","data":[{"id":"qwen3-4b","owned_by":"omlx"}]}"#.utf8)
    let provider = LiveModelBackend.provider(from: 200, data: json, endpoint: omlxEndpoint)
    #expect(provider?.kind == .omlx)
    #expect(provider?.models == ["qwen3-4b"])
    #expect(provider?.requiresAPIKey == false)
}

@Test("Probe: 401 and 403 surface a locked provider instead of hiding the server", arguments: [401, 403])
func probeClassifiesLocked(status: Int) {
    let errorBody = Data(#"{"error":{"message":"API key required"}}"#.utf8)
    let provider = LiveModelBackend.provider(from: status, data: errorBody, endpoint: omlxEndpoint)
    #expect(provider?.requiresAPIKey == true)
    #expect(provider?.models.isEmpty == true)
    #expect(provider?.kind == .mlxServer)   // can't refine without a listing
}

@Test("Probe: other statuses - redirects included - are not a provider",
      arguments: [404, 500, 301, 302, 307, 308])
func probeClassifiesOther(status: Int) {
    #expect(LiveModelBackend.provider(from: status, data: Data(), endpoint: omlxEndpoint) == nil)
}

// MARK: - Endpoint addressing (#110)

@Test("Endpoint: the probe path follows the wire API, so an edit can't desync them")
func endpointListPath() {
    #expect(ModelEndpoint(kind: .lmStudio, port: 1234, api: .openAI).listPath == "/v1/models")
    #expect(ModelEndpoint(kind: .ollama, port: 11434, api: .ollama).listPath == "/api/tags")
}

@Test("Endpoint: 0.0.0.0 is a bind address, so the probe dials loopback instead")
func endpointDialsLoopback() {
    let endpoint = ModelEndpoint(kind: .mlxServer, host: "0.0.0.0", port: 8080, api: .openAI)
    #expect(endpoint.hostBaseURL == "http://0.0.0.0:8080")      // shown as configured
    #expect(endpoint.probeBaseURL == "http://127.0.0.1:8080")   // dialled as routable
}

@Test("Endpoint: a built-in reports being moved off its shipped address")
func endpointEditedFlag() {
    var endpoint = ModelEndpoint.builtIns.first { $0.id == "builtin.lmstudio.1234" }!
    #expect(endpoint.isEdited == false)
    endpoint.port = 4321
    #expect(endpoint.isEdited == true)
    #expect(endpoint.builtInDefault?.port == 1234)

    // Nothing to restore for an endpoint that never shipped with an address.
    var added = ModelEndpoint(kind: .custom, port: 9000, api: .openAI)
    added.port = 9001
    #expect(added.isEdited == false)
    #expect(added.builtInDefault == nil)
}

@Test("Bridge URL: a provider on this Mac still goes through the gateway")
func bridgeURLLoopbackUsesGateway() {
    let url = ModelBridge.containerBaseURL(gateway: "192.168.66.1", host: "127.0.0.1", hostPort: 8080, api: .openAI)
    #expect(url == "http://192.168.66.1:8080/v1")
    // A server bound to every interface is still this Mac, so it takes the gateway too.
    let bound = ModelBridge.containerBaseURL(gateway: "192.168.66.1", host: "0.0.0.0", hostPort: 8080, api: .openAI)
    #expect(bound == "http://192.168.66.1:8080/v1")
}

@Test("Bridge URL: an endpoint on another machine is routable as written")
func bridgeURLRemoteHostUnchanged() {
    let url = ModelBridge.containerBaseURL(gateway: "192.168.66.1", host: "10.0.0.7", hostPort: 8080, api: .openAI)
    #expect(url == "http://10.0.0.7:8080/v1")
}

@Test("Probe: the provider carries its endpoint's identity and address")
func probeCarriesEndpointIdentity() {
    let endpoint = ModelEndpoint(id: "test.remote", kind: .lmStudio, host: "10.0.0.7", port: 4321, api: .openAI)
    let json = Data(#"{"object":"list","data":[{"id":"qwen3-4b"}]}"#.utf8)
    let provider = LiveModelBackend.provider(from: 200, data: json, endpoint: endpoint)

    #expect(provider?.id == "test.remote")
    #expect(provider?.host == "10.0.0.7")
    #expect(provider?.port == 4321)
    #expect(provider?.hostBaseURL == "http://10.0.0.7:4321")
    #expect(provider?.isLoopback == false)

    // A locked provider keeps the same identity, so unlocking it can't move the selection.
    let locked = LiveModelBackend.provider(from: 401, data: Data(), endpoint: endpoint)
    #expect(locked?.id == "test.remote")
}

@Test("Bridge env: a stored API key replaces the placeholder")
func bridgeEnvWithKey() {
    let env = ModelBridge.injectionEnvironment(baseURL: "http://192.168.64.1:8000/v1", api: .openAI, apiKey: "sk-test")
    #expect(env.contains { $0.key == "OPENAI_API_KEY" && $0.value == "sk-test" })

    let open = ModelBridge.injectionEnvironment(baseURL: "http://192.168.64.1:8000/v1", api: .openAI)
    #expect(open.contains { $0.key == "OPENAI_API_KEY" && $0.value == "not-needed" })
}

// MARK: - Probe transport (redirects are not followed)

/// Canned transport for probe tests. Replies from a per-URL script and records every URL
/// the session asks for, so a test can assert what was *not* requested. Redirects are
/// announced via `wasRedirectedTo:` so the session's real redirect machinery - and hence
/// the task delegate - is exercised, rather than the 3xx being handed back as a plain
/// response.
final class ProbeStubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var location: String?
        var body: Data = Data()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var script: [String: Reply] = [:]
    nonisolated(unsafe) private static var requested: [String] = []
    nonisolated(unsafe) private static var authorizations: [String] = []

    /// Installs `script` (keyed by absolute URL) and returns a session wired to this stub.
    static func session(script: [String: Reply]) -> URLSession {
        lock.lock()
        self.script = script
        requested = []
        authorizations = []
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProbeStubProtocol.self]
        return URLSession(configuration: config)
    }

    static var requestedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    /// The `Authorization` header of every request that carried one, in arrival order.
    static var requestedAuthorization: [String] {
        lock.lock()
        defer { lock.unlock() }
        return authorizations
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }

        Self.lock.lock()
        Self.requested.append(url.absoluteString)
        if let auth = request.value(forHTTPHeaderField: "Authorization") {
            Self.authorizations.append(auth)
        }
        let reply = Self.script[url.absoluteString] ?? Reply(status: 404)
        Self.lock.unlock()

        var headers: [String: String] = [:]
        if let location = reply.location { headers["Location"] = location }
        guard let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers
        ) else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let location = reply.location, let next = URL(string: location) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: next), redirectResponse: response)
            // Also complete the task. A refused redirect otherwise leaves this protocol
            // instance loading until the request deadline, which would make the test spend
            // the probe's full timeout proving a point about the delegate.
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private let mlx8080 = ModelEndpoint(id: "test.mlx8080", kind: .mlxServer, port: 8080, api: .openAI)

/// Serialized: the stub keeps its script and its request log in static state.
@Suite("Probe transport", .serialized)
struct ProbeTransportTests {
    /// The shape that froze a Rails dev server: an app on 8080 running with `force_ssl`
    /// redirects the probe to its TLS port, which answers something that parses as a model
    /// listing. The probe must stop at the redirect and never open the second connection.
    @Test("Probe: a redirect is refused, so the target is never requested")
    func probeDoesNotFollowRedirect() async {
        let listing = Data(#"{"object":"list","data":[{"id":"not-a-model-server"}]}"#.utf8)
        let session = ProbeStubProtocol.session(script: [
            "http://127.0.0.1:8080/v1/models": .init(status: 301, location: "https://127.0.0.1:8443/v1/models"),
            "https://127.0.0.1:8443/v1/models": .init(status: 200, body: listing),
        ])

        let provider = await LiveModelBackend.probe(mlx8080, session: session, apiKey: nil)

        #expect(provider == nil)
        #expect(ProbeStubProtocol.requestedURLs == ["http://127.0.0.1:8080/v1/models"])
    }

    /// Guards the test above: without this, a stub that never serves anything would make
    /// the redirect assertion pass for the wrong reason.
    @Test("Probe: a 200 listing on the candidate port is a provider")
    func probeAcceptsDirectListing() async {
        let listing = Data(#"{"object":"list","data":[{"id":"qwen3-4b"}]}"#.utf8)
        let session = ProbeStubProtocol.session(script: [
            "http://127.0.0.1:8080/v1/models": .init(status: 200, body: listing),
        ])

        let provider = await LiveModelBackend.probe(mlx8080, session: session, apiKey: nil)

        #expect(provider?.models == ["qwen3-4b"])
        #expect(ProbeStubProtocol.requestedURLs == ["http://127.0.0.1:8080/v1/models"])
    }

    /// The point of the off switch: a disabled endpoint is not contacted at all. Asserted
    /// on the transport rather than on the returned list, because "no provider" would also
    /// be true if it were probed and simply rejected (#110).
    @Test("Detect: a disabled endpoint is never requested")
    func detectSkipsDisabledEndpoints() async {
        let listing = Data(#"{"object":"list","data":[{"id":"qwen3-4b"}]}"#.utf8)
        let session = ProbeStubProtocol.session(script: [
            "http://127.0.0.1:8080/v1/models": .init(status: 200, body: listing),
            "http://127.0.0.1:1234/v1/models": .init(status: 200, body: listing),
        ])
        var disabled = ModelEndpoint(id: "test.lmstudio", kind: .lmStudio, port: 1234, api: .openAI)
        disabled.isEnabled = false

        let providers = await LiveModelBackend(session: session)
            .detectProviders(endpoints: [mlx8080, disabled], apiKeys: [:])

        #expect(providers.map(\.id) == ["test.mlx8080"])
        #expect(ProbeStubProtocol.requestedURLs == ["http://127.0.0.1:8080/v1/models"])
    }

    /// The key has to reach the wire, not just the keychain: the reported symptom was a
    /// saved key that changed nothing about the request.
    @Test("Detect: a stored key is sent as a bearer token on that endpoint's probe")
    func detectSendsStoredKey() async {
        let listing = Data(#"{"object":"list","data":[{"id":"qwen3-4b"}]}"#.utf8)
        let session = ProbeStubProtocol.session(script: [
            "http://127.0.0.1:8080/v1/models": .init(status: 200, body: listing),
        ])

        _ = await LiveModelBackend(session: session)
            .detectProviders(endpoints: [mlx8080], apiKeys: ["test.mlx8080": "sk-live"])

        #expect(ProbeStubProtocol.requestedAuthorization == ["Bearer sk-live"])
    }
}
