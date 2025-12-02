import SwiftUI

struct ContainerTable: View {
    let containers: [Container]
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    let emptyStateMessage: String

    var body: some View {
        if containers.isEmpty {
            HStack {
                SwiftUI.Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        } else {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Container")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("IP Address")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Hostname")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.separatorColor).opacity(0.5))

                Divider()

                // Container rows
                ForEach(containers, id: \.configuration.id) { container in
                    let containerNetwork = container.networks.first
                    let displayAddress = {
                        guard let address = containerNetwork?.address else { return "N/A" }
                        return address.replacingOccurrences(of: "/24", with: "")
                    }()
                    let displayHostname = {
                        guard let hostname = containerNetwork?.hostname else { return "N/A" }
                        return hostname.hasSuffix(".") ? String(hostname.dropLast()) : hostname
                    }()

                    HStack(spacing: 0) {
                        // Container name (clickable)
                        Button(action: {
                            selectedTab = .containers
                            selectedContainer = container.configuration.id
                        }) {
                            HStack {
                                SwiftUI.Image(systemName: "cube")
                                    .foregroundStyle(container.status.lowercased() == "running" ? .green : .gray)
                                Text(container.configuration.id)
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        // IP Address (clickable)
                        Button(action: {
                            if let address = containerNetwork?.address, address != "N/A" {
                                let cleanAddress = address.replacingOccurrences(of: "/24", with: "")
                                if let url = URL(string: "http://\(cleanAddress)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }) {
                            Text(displayAddress)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(displayAddress != "N/A" ? .blue : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(displayAddress == "N/A")

                        // Hostname (clickable)
                        Button(action: {
                            if let hostname = containerNetwork?.hostname, hostname != "N/A" {
                                let cleanHostname = hostname.hasSuffix(".") ? String(hostname.dropLast()) : hostname
                                if let url = URL(string: "http://\(cleanHostname)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }) {
                            Text(displayHostname)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(displayHostname != "N/A" ? .blue : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(displayHostname == "N/A")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.clear)

                    if container.configuration.id != containers.last?.configuration.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}
