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
