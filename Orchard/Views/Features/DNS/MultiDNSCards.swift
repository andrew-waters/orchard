import AppKit
import SwiftUI

struct MultiDNSCardsView: View {
    @EnvironmentObject var containerService: ContainerService
    let dnsIds: Set<String>
    @Binding var selectedDNSDomainsBinding: Set<String>

    @State private var showDeleteConfirmation = false

    private var selectedDNSList: [DNSDomain] {
        containerService.dnsDomains
            .filter { dnsIds.contains($0.domain) }
            .sorted { $0.domain < $1.domain }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(selectedDNSList, id: \.domain) { domain in
                        DNSSummaryCard(domain: domain) {
                            selectedDNSDomainsBinding = [domain.domain]
                        }
                        .environmentObject(containerService)
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            "Delete selected DNS domains?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Only deletable domains (non-default ones)
            let deletable = selectedDNSList.filter { !$0.isDefault }
            let list = deletable.map { "• \($0.domain)" }.joined(separator: "\n")
            Text("The following \(deletable.count) domain(s) will be deleted (requires admin privileges):\n\n\(list)\n\nThis action cannot be undone.")
        }
    }

    private var header: some View {
        let deletable = selectedDNSList.filter { !$0.isDefault }
        return HStack(spacing: 10) {
            Text("\(selectedDNSList.count) domains selected")
                .font(.headline)

            Spacer()

            if !deletable.isEmpty {
                Button("Delete selected domains") {
                    showDeleteConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func performDelete() {
        let targets = selectedDNSList.filter { !$0.isDefault }.map { $0.domain }
        Task {
            await containerService.deleteDNSDomains(targets)
        }
    }
}

private struct DNSSummaryCard: View {
    @EnvironmentObject var containerService: ContainerService
    let domain: DNSDomain
    let onOpen: () -> Void

    private var containerCountText: String {
        let count = containerService.containers.filter { container in
            if let containerDomain = container.configuration.dns.domain {
                return containerDomain == domain.domain
            }
            return container.configuration.dns.searchDomains.contains(domain.domain)
        }.count
        return count == 0 ? "No containers" : "\(count) container\(count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SwiftUI.Image(systemName: "network")
                    .foregroundColor(domain.isDefault ? .green : .secondary)

                Text(domain.domain)
                    .font(.system(.headline, design: .default))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if domain.isDefault {
                    Text("DEFAULT")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundColor(.green)
                }

                Spacer()

                if !domain.isDefault {
                    Button("Delete") {
                        let alert = NSAlert()
                        alert.messageText = "Delete DNS Domain"
                        alert.informativeText = "Are you sure you want to delete '\(domain.domain)'? This requires administrator privileges."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "Delete")
                        alert.addButton(withTitle: "Cancel")

                        if alert.runModal() == .alertFirstButtonReturn {
                            Task { await containerService.deleteDNSDomains([domain.domain]) }
                        }
                    }
                    .foregroundColor(.red)
                }

                Button("Open") {
                    onOpen()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "Domain Name", value: domain.domain)
                InfoRow(label: "Containers Connected", value: containerCountText)
                InfoRow(label: "Default State", value: domain.isDefault ? "Default Domain" : "Non-default Domain")
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}
