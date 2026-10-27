import SwiftUI

struct DNSDetailView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var dnsService: DNSService
    let domain: String
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    var body: some View {
        if let dnsDomain = dnsService.dnsDomains.first(where: { $0.domain == domain }) {
            VStack(spacing: 0) {
                DNSDetailHeader(domain: domain)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Containers using this domain
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Containers using this domain")
                                .font(.headline)

                            let containersUsingDomain = containerListService.containers.filter {
                                $0.usesDNSDomain(dnsDomain.domain)
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
