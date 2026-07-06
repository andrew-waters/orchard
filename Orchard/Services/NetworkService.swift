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
            isNetworksLoading = true
            self.alertCenter.dismiss()
        }

        do {
            let networks = try await backend.listNetworks()
            if networks != self.networks {
                self.networks = networks
            }
            self.isNetworksLoading = false
        } catch {
            if showLoading {
                self.alertCenter.error("Failed to load networks: \(error.localizedDescription)")
            }
            self.isNetworksLoading = false
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
            self.alertCenter.error("Failed to create network: \(error.localizedDescription)")
            return false
        }
    }

    func delete(_ networkId: String) async {
        do {
            try await backend.deleteNetwork(id: networkId)
            await load()
        } catch {
            self.alertCenter.error("Failed to delete network: \(error.localizedDescription)")
        }
    }
    func deleteNetworks(_ networkIds: [String]) async {
        var deletedCount = 0
        var failedCount = 0
        var lastError: Error?
        for networkId in networkIds {
            if networkId == "default" { continue }
            do {
                try await backend.deleteNetwork(id: networkId)
                deletedCount += 1
            } catch {
                failedCount += 1
                lastError = error
            }
        }
        await load()
        if failedCount > 0 {
            alertCenter.error("Failed to delete \(failedCount) network(s): \(lastError?.localizedDescription ?? "Unknown error")")
        }
    }

}
