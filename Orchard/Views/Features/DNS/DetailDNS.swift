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

                            ContainerTable(
                                containers: containersUsingDomain,
                                selectedTab: $selectedTab,
                                selectedContainer: $selectedContainer,
                                emptyStateMessage: "No containers are using this domain"
                            )
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
