import SwiftUI

struct DNSDetailView: View {
    @EnvironmentObject var containerService: ContainerService
    let domain: String
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    var body: some View {
        if let dnsDomain = containerService.dnsDomains.first(where: { $0.domain == domain }) {
            VStack(alignment: .leading, spacing: 20) {
                Text("DNS Domain: \(dnsDomain.domain)")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Containers using this domain
                VStack(alignment: .leading, spacing: 12) {
                    Text("Containers using this domain")
                        .font(.headline)

                    let containersUsingDomain = containerService.containers.filter { container in
                        // Check if container's DNS domain matches
                        if let containerDomain = container.configuration.dns.domain {
                            return containerDomain == dnsDomain.domain
                        }
                        // Also check search domains as fallback
                        return container.configuration.dns.searchDomains.contains(dnsDomain.domain)
                    }

                    if containersUsingDomain.isEmpty {
                        Text("No containers are using this domain")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
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

                                Text("Network")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 120, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor))

                            Divider()

                            // Container rows
                            ForEach(containersUsingDomain, id: \.configuration.id) { container in
                                HStack {
                                    // Container name (clickable)
                                    Button(action: {
                                        selectedTab = .containers
                                        selectedContainer = container.configuration.id
                                    }) {
                                        HStack {
                                            SwiftUI.Image(systemName: "cube.box")
                                                .foregroundColor(container.status.lowercased() == "running" ? .green : .gray)
                                            Text(container.configuration.id)
                                                .foregroundColor(.primary)
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
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: 100, alignment: .leading)

                                    // Network
                                    Group {
                                        if !container.networks.isEmpty {
                                            Text(container.networks[0].address.replacingOccurrences(of: "/24", with: ""))
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("No network")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(width: 120, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.clear)

                                if container.configuration.id != containersUsingDomain.last?.configuration.id {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(minHeight: 100)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Actions")
                        .font(.headline)

                    Button("Delete Domain") {
                        confirmDNSDomainDeletion(domain: dnsDomain.domain)
                    }
                    .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("Domain not found")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func confirmDNSDomainDeletion(domain: String) {
        let alert = NSAlert()
        alert.messageText = "Delete DNS Domain"
        alert.informativeText = "Are you sure you want to delete '\(domain)'? This requires administrator privileges."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await containerService.deleteDNSDomain(domain) }
        }
    }
}
