import SwiftUI

struct NetworksListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedNetwork: String?
    @Binding var selectedNetworks: Set<String>
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
        List(selection: $selectedNetworks) {
            ForEach(Array(containerService.networks), id: \.id) { network in
                let targetNetworks: [String] = {
                    if selectedNetworks.contains(network.id) && selectedNetworks.count > 1 {
                        return Array(selectedNetworks)
                    }
                    return [network.id]
                }()
                let multiple = targetNetworks.count > 1
                let deletableNetworks = targetNetworks.filter { $0 != "default" }

                NetworkRowView(
                    network: network,
                    connectedContainerCount: connectedContainerCount(for: network),
                    isSelected: selectedNetworks.contains(network.id)
                )
                .environmentObject(containerService)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleRowTap(id: network.id)
                }
                .contextMenu {
                    if !deletableNetworks.isEmpty {
                        Button(multiple ? "Delete \(deletableNetworks.count) Networks" : "Delete Network", role: .destructive) {
                            confirmNetworksDeletion(networkIds: deletableNetworks)
                        }
                    }
                }
                .tag(network.id)
            }
        }
        .listStyle(PlainListStyle())
        .background(
            Button(action: selectAllNetworks) {
                EmptyView()
            }
            .keyboardShortcut("a", modifiers: .command)
        )
        .animation(.easeInOut(duration: 0.3), value: containerService.networks)
        .focused($listFocusedTab, equals: .networks)
        .onChange(of: selectedNetwork) { _, newValue in
            lastSelectedNetwork = newValue
        }
    }

    private struct NetworkRowView: View {
        let network: ContainerNetwork
        let connectedContainerCount: Int
        let isSelected: Bool
        @EnvironmentObject var containerService: ContainerService

        var body: some View {
            let containerText = "\(connectedContainerCount) container\(connectedContainerCount == 1 ? "" : "s")"

            ListItemRow(
                icon: "arrow.down.left.arrow.up.right",
                iconColor: hasRunningContainers ? .green : .secondary,
                primaryText: network.id,
                secondaryLeftText: network.status.address ?? "No address",
                secondaryRightText: containerText,
                isSelected: isSelected
            )
        }

        private var hasRunningContainers: Bool {
            return containerService.containers.contains { container in
                container.status.lowercased() == "running" &&
                container.networks.contains { containerNetwork in
                    containerNetwork.network == network.id
                }
            }
        }
    }

    private func connectedContainerCount(for network: ContainerNetwork) -> Int {
        return containerService.containers.filter { container in
            container.networks.contains { containerNetwork in
                containerNetwork.network == network.id
            }
        }.count
    }

    private func handleRowTap(id: String) {
        let orderedIds = containerService.networks.map { $0.id }
        SelectionHandler.handleSelection(
            clickedId: id,
            orderedIds: orderedIds,
            selectedSet: &selectedNetworks,
            lastSelectedId: &lastSelectedNetwork
        )
    }

    private func selectAllNetworks() {
        let orderedIds = containerService.networks.map { $0.id }
        selectedNetworks = Set(orderedIds)
    }

    private func confirmNetworksDeletion(networkIds: [String]) {
        let alert = NSAlert()
        alert.messageText = networkIds.count > 1 ? "Delete Networks" : "Delete Network"
        let idsList = networkIds.joined(separator: ", ")
        alert.informativeText = "Are you sure you want to delete \(networkIds.count > 1 ? "\(networkIds.count) networks (\(idsList))" : "'\(networkIds[0])'")? This requires administrator privileges."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await containerService.deleteNetworks(networkIds) }
        }
    }
}
