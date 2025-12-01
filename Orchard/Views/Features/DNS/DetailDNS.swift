import SwiftUI

struct DNSDetailView: View {
    @EnvironmentObject var containerService: ContainerService
    let domain: String
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    var body: some View {
        if let dnsDomain = containerService.dnsDomains.first(where: { $0.domain == domain }) {
            VStack(spacing: 0) {
                DNSDetailHeader(domain: domain)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
                                        Button(action: {
                                            selectedTab = .containers
                                            selectedContainer = container.configuration.id
                                        }) {
                                            HStack {
                                                Text(container.configuration.id)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)

                                                HStack {
                                                    Circle()
                                                        .fill(container.status.lowercased() == "running" ? .green : .gray)
                                                        .frame(width: 8, height: 8)
                                                    Text(container.status)
                                                        .foregroundColor(.secondary)
                                                }
                                                .frame(width: 100, alignment: .leading)

                                                Text(container.networks.isEmpty ? "No network" : container.networks[0].network)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 120, alignment: .leading)
                                            }
                                        }
                                        .buttonStyle(.plain)
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

                            HStack(spacing: 12) {
                                if !dnsDomain.isDefault {
                                    Button("Make Default") {
                                        DispatchQueue.main.async {
                                            Task {
                                                await containerService.setDefaultDNSDomain(dnsDomain.domain)
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Spacer()
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
        } else {
            Text("Domain not found")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }


}
