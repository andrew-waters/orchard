import AppKit
import SwiftUI

struct MultiNetworkCardsView: View {
    @EnvironmentObject var containerService: ContainerService
    let networkIds: Set<String>
    @Binding var selectedNetworksBinding: Set<String>

    @State private var showDeleteConfirmation = false

    private var selectedNetworksList: [ContainerNetwork] {
        containerService.networks
            .filter { networkIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(selectedNetworksList, id: \.id) { network in
                        NetworkSummaryCard(network: network) {
                            selectedNetworksBinding = [network.id]
                        }
                        .environmentObject(containerService)
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            "Delete selected networks?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Only deletable networks (non-default ones)
            let deletable = selectedNetworksList.filter { $0.id != "default" }
            let list = deletable.map { "• \($0.id)" }.joined(separator: "\n")
            Text("The following \(deletable.count) network(s) will be deleted (requires admin privileges):\n\n\(list)\n\nThis action cannot be undone.")
        }
    }

    private var header: some View {
        let deletable = selectedNetworksList.filter { $0.id != "default" }
        return HStack(spacing: 10) {
            Text("\(selectedNetworksList.count) networks selected")
                .font(.headline)

            Spacer()

            if !deletable.isEmpty {
                Button("Delete selected networks") {
                    showDeleteConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func performDelete() {
        let targets = selectedNetworksList.filter { $0.id != "default" }.map { $0.id }
        Task {
            await containerService.deleteNetworks(targets)
        }
    }
}

private struct NetworkSummaryCard: View {
    @EnvironmentObject var containerService: ContainerService
    let network: ContainerNetwork
    let onOpen: () -> Void

    private var hasRunningContainers: Bool {
        containerService.containers.contains { container in
            container.status.lowercased() == "running" &&
            container.networks.contains { containerNetwork in
                containerNetwork.network == network.id
            }
        }
    }

    private var connectedContainerCount: Int {
        containerService.containers.filter { container in
            container.networks.contains { containerNetwork in
                containerNetwork.network == network.id
            }
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SwiftUI.Image(systemName: "arrow.down.left.arrow.up.right")
                    .foregroundColor(hasRunningContainers ? .green : .secondary)

                Text(network.id)
                    .font(.system(.headline, design: .default))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if network.id != "default" {
                    Button("Delete") {
                        let alert = NSAlert()
                        alert.messageText = "Delete Network"
                        alert.informativeText = "Are you sure you want to delete '\(network.id)'? This requires administrator privileges."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Delete")
                        alert.addButton(withTitle: "Cancel")

                        if alert.runModal() == .alertFirstButtonReturn {
                            Task { await containerService.deleteNetworks([network.id]) }
                        }
                    }
                    .foregroundColor(.red)
                }

                Button("Open") {
                    onOpen()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "Network ID", value: network.id)
                InfoRow(label: "State", value: network.state)
                InfoRow(label: "Subnet Address", value: network.status.address ?? "No address")
                InfoRow(label: "Gateway", value: network.status.gateway ?? "No gateway")
                InfoRow(label: "Connected Containers", value: "\(connectedContainerCount) container\(connectedContainerCount == 1 ? "" : "s")")
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}
