import SwiftUI

// MARK: - Network Detail Header
struct NetworkDetailHeader: View {
    let network: ContainerNetwork
    @EnvironmentObject var containerService: ContainerService

    private var connectedContainers: [Container] {
        containerService.containers.filter { container in
            container.networks.contains { containerNetwork in
                containerNetwork.network == network.id
            }
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(network.id)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                DetailViewButton(
                    icon: "trash.fill",
                    accessibilityText: "Delete this network",
                    action: {
                        confirmNetworkDeletion(networkId: network.id)
                    },
                    isDisabled: network.id == "default" || !connectedContainers.isEmpty
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(.regularMaterial, in: Rectangle())
    }

    private func confirmNetworkDeletion(networkId: String) {
        let alert = NSAlert()
        alert.messageText = "Delete Network"
        alert.informativeText = "Are you sure you want to delete '\(networkId)'? This requires administrator privileges."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await containerService.deleteNetwork(networkId) }
        }
    }
}
