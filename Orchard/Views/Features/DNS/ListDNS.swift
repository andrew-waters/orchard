import SwiftUI

struct DNSListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedDNSDomain: String?
    @Binding var selectedDNSDomains: Set<String>
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
        List(selection: $selectedDNSDomains) {
            ForEach(containerService.dnsDomains) { domain in
                let targetDomains: [String] = {
                    if selectedDNSDomains.count > 1 && selectedDNSDomains.contains(domain.domain) {
                        return Array(selectedDNSDomains)
                    }
                    return [domain.domain]
                }()
                let multiple = targetDomains.count > 1

                DNSRowView(
                    domain: domain,
                    containerCountText: containerCount(for: domain),
                    isSelected: selectedDNSDomains.contains(domain.domain)
                )
                .environmentObject(containerService)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleRowTap(id: domain.domain)
                }
                .contextMenu {
                    if !multiple && !domain.isDefault {
                        Button("Make Default") {
                            let currentSelection = selectedDNSDomain
                            Task {
                                await containerService.setDefaultDNSDomain(domain.domain)
                                selectedDNSDomain = currentSelection
                            }
                        }
                    }

                    // Only allow deleting non-default domains
                    let deletableDomains = targetDomains.filter { dom in
                        if let d = containerService.dnsDomains.first(where: { $0.domain == dom }) {
                            return !d.isDefault
                        }
                        return true
                    }

                    if !deletableDomains.isEmpty {
                        Button(multiple ? "Delete \(deletableDomains.count) Domains" : "Delete Domain", role: .destructive) {
                            confirmDNSDomainsDeletion(domains: deletableDomains)
                        }
                    }
                }
                .tag(domain.domain)
            }
        }
        .listStyle(PlainListStyle())
        .background(
            Button(action: selectAllDNSDomains) {
                EmptyView()
            }
            .keyboardShortcut("a", modifiers: .command)
        )
        .animation(.easeInOut(duration: 0.3), value: containerService.dnsDomains)
        .focused($listFocusedTab, equals: .dns)
        .onChange(of: selectedDNSDomain) { _, newValue in
            lastSelectedDNSDomain = newValue
        }
    }

    private struct DNSRowView: View {
        let domain: DNSDomain
        let containerCountText: String
        let isSelected: Bool

        var body: some View {
            let rightText = domain.isDefault ? "DEFAULT" : nil

            ListItemRow(
                icon: "network",
                iconColor: domain.isDefault ? .green : .secondary,
                primaryText: domain.domain,
                secondaryLeftText: containerCountText,
                secondaryRightText: rightText,
                isSelected: isSelected
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

    private func handleRowTap(id: String) {
        let orderedIds = containerService.dnsDomains.map { $0.domain }
        SelectionHandler.handleSelection(
            clickedId: id,
            orderedIds: orderedIds,
            selectedSet: &selectedDNSDomains,
            lastSelectedId: &lastSelectedDNSDomain
        )
    }

    private func selectAllDNSDomains() {
        let orderedIds = containerService.dnsDomains.map { $0.domain }
        selectedDNSDomains = Set(orderedIds)
    }

    private func confirmDNSDomainsDeletion(domains: [String]) {
        let alert = NSAlert()
        alert.messageText = domains.count > 1 ? "Delete DNS Domains" : "Delete DNS Domain"
        let domainsList = domains.joined(separator: ", ")
        alert.informativeText = "Are you sure you want to delete \(domains.count > 1 ? "\(domains.count) domains (\(domainsList))" : "'\(domains[0])'")? This requires administrator privileges."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await containerService.deleteDNSDomains(domains) }
        }
    }
}
