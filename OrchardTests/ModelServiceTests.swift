import Testing
import Foundation
@testable import Orchard

// ModelService detection + the network→bridge-environment resolution. Detection is
// best-effort and never alerts, so there is no error path to assert.

private func makeProvider(
    kind: ModelProvider.Kind = .mlxServer,
    port: UInt16 = 8080,
    api: ModelAPIStyle = .openAI,
    models: [String] = ["llama-3.2-1b"]
) -> ModelProvider {
    ModelProvider(kind: kind, port: port, api: api, models: models)
}

private func makeNetwork(id: String = "default", gateway: String? = "192.168.66.1") -> ContainerNetwork {
    ContainerNetwork(
        id: id,
        state: "running",
        config: NetworkConfig(labels: [:], id: id),
        status: NetworkStatus(gateway: gateway, address: "192.168.66.0/24")
    )
}

// MARK: - load

@Test("Models load: publishes detected providers and clears loading")
@MainActor
func modelsLoadSuccess() async {
    let backend = MockModelBackend(providers: [makeProvider()])
    let service = ModelService(backend: backend)

    await service.load()

    #expect(service.providers.count == 1)
    #expect(service.providers.first?.models == ["llama-3.2-1b"])
    #expect(service.isLoading == false)
    #expect(backend.detectCount == 1)
}

@Test("Models load: no providers running publishes an empty list, not an error")
@MainActor
func modelsLoadEmpty() async {
    let service = ModelService(backend: MockModelBackend(providers: []))

    await service.load()

    #expect(service.providers.isEmpty)
    #expect(service.isLoading == false)
}

// MARK: - bridgeEnvironment

@Test("Bridge env: resolves the network gateway into an OpenAI base URL")
@MainActor
func bridgeEnvResolvesGateway() {
    let service = ModelService(backend: MockModelBackend())
    let env = service.bridgeEnvironment(for: makeProvider(port: 8080, api: .openAI), on: makeNetwork(gateway: "192.168.66.1"))

    #expect(env?.first { $0.key == "OPENAI_BASE_URL" }?.value == "http://192.168.66.1:8080/v1")
}

@Test("Bridge env: a network without a gateway yields nil (no route to host)")
@MainActor
func bridgeEnvNoGateway() {
    let service = ModelService(backend: MockModelBackend())

    #expect(service.bridgeEnvironment(for: makeProvider(), on: makeNetwork(gateway: nil)) == nil)
    #expect(service.bridgeEnvironment(for: makeProvider(), on: makeNetwork(gateway: "")) == nil)
}
