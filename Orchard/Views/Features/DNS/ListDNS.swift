import SwiftUI

struct DNSListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedDNSDomain: String?
    @Binding var lastSelectedDNSDomain: String?
    @Binding var showAddDNSDomainSheet: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddDNSDomainSheet) {
            AddDomainView()
                .environmentObject(containerService)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if containerService.isDNSLoading {
            loadingView
        } else if containerService.dnsDomains.isEmpty {
            emptyStateView
        } else {
            dnsListView
        }
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .padding()
            Text("Loading DNS domains...")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack {
            SwiftUI.Image(systemName: "network.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            Text("No DNS Domains")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Add a domain to get started")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dnsListView: some View {
        List(selection: $selectedDNSDomain) {
            ForEach(containerService.dnsDomains) { domain in
                DNSRowView(
                    domain: domain,
                    containerCountText: containerCount(for: domain)
                )
                .environmentObject(containerService)
                .contextMenu {
                    if !domain.isDefault {
                        Button("Make Default") {
                            let currentSelection = selectedDNSDomain
                            Task {
                                await containerService.setDefaultDNSDomain(domain.domain)
                                selectedDNSDomain = currentSelection
                            }
                        }
                    }

                    if !domain.isDefault {
                        Button("Delete Domain", role: .destructive) {
                            confirmDNSDomainDeletion(domain: domain.domain)
                        }
                    }
                }
                .tag(domain.domain)
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: containerService.dnsDomains)
        .focused($listFocusedTab, equals: .dns)
        .onChange(of: selectedDNSDomain) { _, newValue in
            lastSelectedDNSDomain = newValue
        }
    }

    private struct DNSRowView: View {
        let domain: DNSDomain
        let containerCountText: String

        var body: some View {
            let rightText = domain.isDefault ? "DEFAULT" : nil

            ListItemRow(
                icon: "network",
                iconColor: .blue,
                primaryText: domain.domain,
                secondaryLeftText: containerCountText,
                secondaryRightText: rightText,
                isSelected: false
            )
        }
    }

        private func containerCount(for dnsDomain: DNSDomain) -> String {
            let count = containerService.containers.filter { container in
                if let containerDomain = container.configuration.dns.domain {
                    return containerDomain == dnsDomain.domain
                }
                return container.configuration.dns.searchDomains.contains(dnsDomain.domain)
            }.count

            return count == 0 ? "No containers" : "\(count) container\(count == 1 ? "" : "s")"
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
