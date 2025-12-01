import SwiftUI

// MARK: - DNS Detail Header
struct DNSDetailHeader: View {
    let domain: String
    @EnvironmentObject var containerService: ContainerService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(domain)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                DetailViewButton(
                    icon: "trash.fill",
                    accessibilityText: "Delete this DNS domain",
                    action: {
                        confirmDNSDomainDeletion(domain: domain)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
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
