import Testing
import Foundation
@testable import Orchard

// NetworkService state transitions, against a directly-constructed service.
// Backed by MockContainerBackend (records network calls, injects errors).

@MainActor
private func makeNetworkService(_ backend: MockContainerBackend = MockContainerBackend())
    -> (service: NetworkService, alert: AlertCenter) {
    let alert = AlertCenter()
    return (NetworkService(backend: backend, alertCenter: alert), alert)
}

// MARK: - load

@MainActor
@Test("Networks load: success publishes the list and clears the spinner")
func networkLoadSuccess() async {
    let backend = MockContainerBackend()
    backend.networks = [makeNetwork(id: "bridge"), makeNetwork(id: "custom")]
    let (service, _) = makeNetworkService(backend)

    await service.load(showLoading: true)

    #expect(service.networks.map(\.id) == ["bridge", "custom"])
    #expect(service.isNetworksLoading == false)
}

@MainActor
@Test(
    "Networks load: a failure alerts only when user-initiated and leaves networks intact",
    arguments: [(showLoading: true, expectsAlert: true), (showLoading: false, expectsAlert: false)]
)
func networkLoadFailure(_ c: (showLoading: Bool, expectsAlert: Bool)) async {
    let backend = MockContainerBackend()
    backend.networks = [makeNetwork(id: "bridge")]
    let (service, alert) = makeNetworkService(backend)
    await service.load(showLoading: false)      // seed a network

    backend.listNetworksError = NotConfigured()
    await service.load(showLoading: c.showLoading)

    #expect((alert.current != nil) == c.expectsAlert)
    #expect(service.isNetworksLoading == false)
    #expect(service.networks.map(\.id) == ["bridge"])   // failed reload leaves the list intact
}

// MARK: - create

@MainActor
@Test("Networks create: labels parse as KEY=VALUE, bare labels get an empty value")
func networkCreateParsesLabels() async {
    let backend = MockContainerBackend()
    let (service, alert) = makeNetworkService(backend)

    let ok = await service.create(name: "app-net", labels: ["env=prod", "bare", "team=b=c"])

    #expect(ok == true)
    let recorded = backend.createdNetworks.first
    #expect(recorded?.name == "app-net")
    #expect(recorded?.labels == ["env": "prod", "bare": "", "team": "b=c"])  // maxSplits: 1
    #expect(alert.current == nil)
}

@MainActor
@Test("Networks create: a failure alerts and returns false")
func networkCreateFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.createNetworkError = NotConfigured()
    let (service, alert) = makeNetworkService(backend)

    let ok = await service.create(name: "app-net")

    #expect(ok == false)
    #expect(alert.current != nil)
}

// MARK: - delete

@MainActor
@Test("Networks delete: success removes the network via a reload")
func networkDeleteSuccessReloads() async {
    let backend = MockContainerBackend()
    backend.networks = [makeNetwork(id: "gone")]
    let (service, _) = makeNetworkService(backend)
    await service.load(showLoading: false)   // has "gone"

    backend.networks = []                    // backend no longer lists it
    await service.delete("gone")

    #expect(backend.deletedNetworkIds == ["gone"])
    #expect(service.networks.isEmpty)         // reload picked up the removal
}

@MainActor
@Test("Networks delete: a failure alerts")
func networkDeleteFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteNetworkError = NotConfigured()
    let (service, alert) = makeNetworkService(backend)

    await service.delete("stuck")

    #expect(alert.current != nil)
}
