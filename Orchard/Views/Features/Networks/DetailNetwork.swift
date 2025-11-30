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

            VStack(alignment: .leading, spacing: 20) {
                // Network header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SwiftUI.Image(systemName: networkIcon(for: network))
                            .foregroundStyle(networkColor(for: network))
                            .font(.system(size: 24))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(network.id)
                                .font(.largeTitle)
                                .fontWeight(.bold)

                            HStack {
                                Text(network.state.capitalized)
                                    .foregroundStyle(network.state == "running" ? .green : .secondary)

                                Text("•")
                                    .foregroundStyle(.secondary)

                                if !network.config.labels.isEmpty {
                                    Text("\(network.config.labels.count) label\(network.config.labels.count == 1 ? "" : "s")")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }

                        Spacer()
                    }
                }

                // Network details
                VStack(alignment: .leading, spacing: 12) {
                    Text("Network Details")
                        .font(.headline)

                    VStack(spacing: 0) {
                        networkDetailRow(label: "Network ID", value: network.id)
                        Divider().padding(.leading, 100)
                        networkDetailRow(label: "State", value: network.state.capitalized)

                        if !network.config.labels.isEmpty {
                            Divider().padding(.leading, 100)
                            networkDetailRow(label: "Labels", value: "\(network.config.labels.count) label\(network.config.labels.count == 1 ? "" : "s")")
                        }

                        if let address = network.status.address {
                            Divider().padding(.leading, 100)
                            networkDetailRow(label: "Address Range", value: address)
                        }

                        if let gateway = network.status.gateway {
                            Divider().padding(.leading, 100)
                            networkDetailRow(label: "Gateway", value: gateway)
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Labels section
                if !network.config.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Labels")
                            .font(.headline)

                        VStack(spacing: 0) {
                            ForEach(Array(network.config.labels.sorted(by: { $0.key < $1.key })), id: \.key) { label in
                                networkDetailRow(label: label.key, value: label.value)
                                if label.key != network.config.labels.sorted(by: { $0.key < $1.key }).last?.key {
                                    Divider().padding(.leading, 100)
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }

                // Connected containers
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connected Containers")
                        .font(.headline)



                    if connectedContainers.isEmpty {
                        HStack {
                            SwiftUI.Image(systemName: "cube.transparent")
                                .foregroundStyle(.secondary)
                            Text("No containers are connected to this network")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Text("Container")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("Status")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 100, alignment: .leading)

                                Text("IP Address")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 130, alignment: .leading)

                                Text("Hostname")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 120, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.separatorColor).opacity(0.5))

                            Divider()

                            // Container rows
                            ForEach(connectedContainers, id: \.configuration.id) { container in
                                let containerNetwork = container.networks.first { $0.network == network.id }

                                HStack {
                                    // Container name (clickable)
                                    Button(action: {
                                        selectedTab = .containers
                                        selectedContainer = container.configuration.id
                                    }) {
                                        HStack {
                                            SwiftUI.Image(systemName: "cube")
                                                .foregroundStyle(container.status.lowercased() == "running" ? .green : .gray)
                                            Text(container.configuration.id)
                                                .foregroundStyle(.primary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    // Status
                                    HStack {
                                        Circle()
                                            .fill(container.status.lowercased() == "running" ? .green : .gray)
                                            .frame(width: 8, height: 8)
                                        Text(container.status)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 100, alignment: .leading)

                                    // IP Address
                                    Text(containerNetwork?.address ?? "N/A")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 130, alignment: .leading)

                                    // Hostname
                                    Text(containerNetwork?.hostname ?? "N/A")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.clear)

                                if container.configuration.id != connectedContainers.last?.configuration.id {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }

                // Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Actions")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button("Delete Network") {
                            confirmNetworkDeletion(networkId: network.id)
                        }
                        .foregroundStyle(.red)
                        .disabled(network.id == "default" || !connectedContainers.isEmpty)

                        Spacer()
                    }

                    if network.id == "default" {
                        Text("The default network cannot be deleted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !connectedContainers.isEmpty {
                        Text("Network cannot be deleted while containers are connected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        switch network.state.lowercased() {
        case "running":
            return .green
        case "stopped":
            return .red
        default:
            return .gray
        }
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
