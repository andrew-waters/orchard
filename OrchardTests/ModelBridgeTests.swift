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

private let omlxCandidate = LiveModelBackend.Candidate(kind: .mlxServer, port: 8000, api: .openAI, listPath: "/v1/models")

@Test("Probe: a 200 with an oMLX listing yields an unlocked oMLX provider")
func probeClassifiesOK() {
    let json = Data(#"{"object":"list","data":[{"id":"qwen3-4b","owned_by":"omlx"}]}"#.utf8)
    let provider = LiveModelBackend.provider(from: 200, data: json, candidate: omlxCandidate)
    #expect(provider?.kind == .omlx)
    #expect(provider?.models == ["qwen3-4b"])
    #expect(provider?.requiresAPIKey == false)
}

@Test("Probe: 401 and 403 surface a locked provider instead of hiding the server", arguments: [401, 403])
func probeClassifiesLocked(status: Int) {
    let errorBody = Data(#"{"error":{"message":"API key required"}}"#.utf8)
    let provider = LiveModelBackend.provider(from: status, data: errorBody, candidate: omlxCandidate)
    #expect(provider?.requiresAPIKey == true)
    #expect(provider?.models.isEmpty == true)
    #expect(provider?.kind == .mlxServer)   // can't refine without a listing
}

@Test("Probe: other statuses - redirects included - are not a provider",
      arguments: [404, 500, 301, 302, 307, 308])
func probeClassifiesOther(status: Int) {
    #expect(LiveModelBackend.provider(from: status, data: Data(), candidate: omlxCandidate) == nil)
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

    /// Installs `script` (keyed by absolute URL) and returns a session wired to this stub.
    static func session(script: [String: Reply]) -> URLSession {
        lock.lock()
        self.script = script
        requested = []
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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }

        Self.lock.lock()
        Self.requested.append(url.absoluteString)
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

private let mlx8080 = LiveModelBackend.Candidate(kind: .mlxServer, port: 8080, api: .openAI, listPath: "/v1/models")

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
}
