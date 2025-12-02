import SwiftUI

struct NetworkDetailView: View {
    @EnvironmentObject var containerService: ContainerService
    let networkId: String
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    var body: some View {
        if let network = containerService.networks.first(where: { $0.id == networkId }) {
            let connectedContainers = containerService.containers.filter { container in
                container.networks.contains { containerNetwork in
                    containerNetwork.network == network.id
                }
            }

            VStack(spacing: 0) {
                NetworkDetailHeader(network: network)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Network details
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(spacing: 0) {
                                networkDetailRow(label: "Network ID", value: network.id)

                                Divider().padding(.leading, 120)
                                networkDetailRow(label: "Address Range", value: network.status.address ?? "N/A")

                                Divider().padding(.leading, 120)
                                networkDetailRow(label: "Gateway", value: network.status.gateway ?? "N/A")

                                Divider().padding(.leading, 120)
                                networkLabelsRow(labels: network.config.labels)
                            }
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }

                        // Connected containers
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Containers using this network")
                                .font(.headline)



                            ContainerTable(
                                containers: connectedContainers,
                                selectedTab: $selectedTab,
                                selectedContainer: $selectedContainer,
                                emptyStateMessage: "No containers are connected to this network"
                            )
                        }
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
        } else {
            Text("Network not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func networkDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 13, design: label.contains("Address") || label.contains("Gateway") ? .monospaced : .default))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func networkIcon(for network: ContainerNetwork) -> String {
        return "wifi"
    }

    private func networkColor(for network: ContainerNetwork) -> Color {
        return .blue
    }

    @ViewBuilder
    private func networkLabelsRow(labels: [String: String]) -> some View {
        HStack(alignment: .top) {
            Text("Labels")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)

            if labels.isEmpty {
                Text("None")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        Text("\(key): \(value)")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(.primary)
                            .cornerRadius(6)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

}
