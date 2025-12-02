import SwiftUI

struct NetworksListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedNetwork: String?
    @Binding var lastSelectedNetwork: String?
    @Binding var showAddNetworkSheet: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddNetworkSheet) {
            AddNetworkView()
                .environmentObject(containerService)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if containerService.isNetworksLoading {
            loadingView
        } else if containerService.networks.isEmpty {
            emptyStateView
        } else {
            networksListView
        }
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .padding()
            Text("Loading networks...")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack {
            SwiftUI.Image(systemName: "wifi.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text("No Networks")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create a network to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var networksListView: some View {
        List(selection: $selectedNetwork) {
            ForEach(Array(containerService.networks), id: \.id) { network in
                NetworkRowView(
                    network: network,
                    connectedContainerCount: connectedContainerCount(for: network),
                    selectedNetwork: selectedNetwork
                )
                .environmentObject(containerService)
                .contextMenu {
                    Button("Delete Network", role: .destructive) {
                        confirmNetworkDeletion(networkId: network.id)
                    }
                    .disabled(network.id == "default")
                }
                .tag(network.id)
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: containerService.networks)
        .focused($listFocusedTab, equals: .networks)
        .onChange(of: selectedNetwork) { _, newValue in
            lastSelectedNetwork = newValue
        }
    }

    private struct NetworkRowView: View {
        let network: ContainerNetwork
        let connectedContainerCount: Int
        let selectedNetwork: String?

        var body: some View {
            let containerText = "\(connectedContainerCount) container\(connectedContainerCount == 1 ? "" : "s")"

            ListItemRow(
                icon: "wifi",
                iconColor: .green,
                primaryText: network.id,
                secondaryLeftText: network.status.address ?? "No address",
                secondaryRightText: containerText,
                isSelected: selectedNetwork == network.id
            )
        }
    }

    private func connectedContainerCount(for network: ContainerNetwork) -> Int {
        return containerService.containers.filter { container in
            container.networks.contains { containerNetwork in
                containerNetwork.network == network.id
            }
        }.count
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
