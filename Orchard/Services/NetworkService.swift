import Foundation

/// Owns container network state and lifecycle, backed by the XPC network client.
@MainActor
final class NetworkService: ObservableObject {
    @Published var networks: [ContainerNetwork] = []
    @Published var isNetworksLoading = false

    private let backend: ContainerBackend
    private let alertCenter: AlertCenter

    init(backend: ContainerBackend, alertCenter: AlertCenter) {
        self.backend = backend
        self.alertCenter = alertCenter
    }

    func load(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isNetworksLoading = true
                self.alertCenter.dismiss()
            }
        }

        do {
            let networks = try await backend.listNetworks()
            await MainActor.run {
                self.networks = networks
                self.isNetworksLoading = false
            }
        } catch {
            await MainActor.run {
                if showLoading {
                    self.alertCenter.error("Failed to load networks: \(error.localizedDescription)")
                }
                self.isNetworksLoading = false
            }
        }
    }

    @discardableResult
    func create(name: String, subnet: String? = nil, labels: [String] = []) async -> Bool {
        do {
            var labelDict: [String: String] = [:]
            for label in labels {
                let parts = label.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    labelDict[String(parts[0])] = String(parts[1])
                } else {
                    labelDict[label] = ""
                }
            }

            try await backend.createNetwork(name: name, labels: labelDict)
            await load()
            return true
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to create network: \(error.localizedDescription)")
            }
            return false
        }
    }

    func delete(_ networkId: String) async {
        do {
            try await backend.deleteNetwork(id: networkId)
            await load()
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to delete network: \(error.localizedDescription)")
            }
        }
    }
}
