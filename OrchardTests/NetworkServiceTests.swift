import Testing
import Foundation
@testable import Orchard

// NetworkService state transitions, driven through the facade's `networkService`.
// Backed by MockContainerBackend (records network calls, injects errors).

// MARK: - load

@MainActor
@Test("Networks load: success publishes the list and clears the spinner")
func networkLoadSuccess() async {
    let backend = MockContainerBackend()
    backend.networks = [makeNetwork(id: "bridge"), makeNetwork(id: "custom")]
    let service = makeService(backend: backend)

    await service.networkService.load(showLoading: true)

    #expect(service.networkService.networks.map(\.id) == ["bridge", "custom"])
    #expect(service.networkService.isNetworksLoading == false)
}

@MainActor
@Test("Networks load: a user-initiated failure alerts and clears the spinner")
func networkLoadUserFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.listNetworksError = NotConfigured()
    let service = makeService(backend: backend)

    await service.networkService.load(showLoading: true)

    #expect(service.alertCenter.current != nil)
    #expect(service.networkService.isNetworksLoading == false)
}

@MainActor
@Test("Networks load: a background failure stays silent and leaves existing networks intact")
func networkLoadBackgroundFailureSilent() async {
    let backend = MockContainerBackend()
    backend.networks = [makeNetwork(id: "bridge")]
    let service = makeService(backend: backend)
    await service.networkService.load(showLoading: true)   // seed a network

    backend.listNetworksError = NotConfigured()
    await service.networkService.load(showLoading: false)  // background poll fails

    #expect(service.alertCenter.current == nil)
    #expect(service.networkService.networks.map(\.id) == ["bridge"])   // unchanged
}

// MARK: - create

@MainActor
@Test("Networks create: labels parse as KEY=VALUE, bare labels get an empty value")
func networkCreateParsesLabels() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)

    let ok = await service.networkService.create(
        name: "app-net", labels: ["env=prod", "bare", "team=b=c"]
    )

    #expect(ok == true)
    let recorded = backend.createdNetworks.first
    #expect(recorded?.name == "app-net")
    #expect(recorded?.labels == ["env": "prod", "bare": "", "team": "b=c"])  // maxSplits: 1
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("Networks create: a failure alerts and returns false")
func networkCreateFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.createNetworkError = NotConfigured()
    let service = makeService(backend: backend)

    let ok = await service.networkService.create(name: "app-net")

    #expect(ok == false)
    #expect(service.alertCenter.current != nil)
}

// MARK: - delete

@MainActor
@Test("Networks delete: success removes the network via a reload")
func networkDeleteSuccessReloads() async {
    let backend = MockContainerBackend()
    backend.networks = [makeNetwork(id: "gone")]
    let service = makeService(backend: backend)
    await service.networkService.load(showLoading: false)   // has "gone"

    backend.networks = []                                    // backend no longer lists it
    await service.networkService.delete("gone")

    #expect(backend.deletedNetworkIds == ["gone"])
    #expect(service.networkService.networks.isEmpty)         // reload picked up the removal
}

@MainActor
@Test("Networks delete: a failure alerts")
func networkDeleteFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteNetworkError = NotConfigured()
    let service = makeService(backend: backend)

    await service.networkService.delete("stuck")

    #expect(service.alertCenter.current != nil)
}
