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
            ForEach(containerService.networks) { network in
                networkRowView(network: network)
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: containerService.networks)
        .focused($listFocusedTab, equals: .networks)
        .onChange(of: selectedNetwork) { _, newValue in
            lastSelectedNetwork = newValue
        }
    }

    @ViewBuilder
    private func networkRowView(network: ContainerNetwork) -> some View {
        HStack(spacing: 8) {
            SwiftUI.Image(systemName: networkIcon(for: network))
                .foregroundStyle(networkColor(for: network))
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(network.id)
                    .font(.system(size: 13, weight: .medium))

                networkInfoRow(network: network)

                if let address = network.status.address {
                    Text(address)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(8)
        .contextMenu {
            Button("Delete Network") {
                confirmNetworkDeletion(networkId: network.id)
            }
            .disabled(network.id == "default")
        }
        .tag(network.id)
    }

    @ViewBuilder
    private func networkInfoRow(network: ContainerNetwork) -> some View {
        HStack(spacing: 8) {
            // Labels count
            if !network.config.labels.isEmpty {
                Text("\(network.config.labels.count) label\(network.config.labels.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(3)
            }

            Spacer()
        }
    }



    private func networkIcon(for network: ContainerNetwork) -> String {
        return "wifi"
    }

    private func networkColor(for network: ContainerNetwork) -> Color {
        return .blue
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
