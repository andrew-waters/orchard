import SwiftUI

/// Networks in the same table as everything else, so a compose project's networks read the
/// way its containers do rather than as a footnote under them.
struct NetworkTable: View {
    /// A row for a network that should exist and does not yet.
    struct Placeholder: Identifiable {
        let name: String
        let note: ResourceTable.Note

        var id: String { name }
    }

    let networks: [ContainerNetwork]
    var placeholders: [Placeholder] = []
    /// What the status column says. By default the network's own state.
    var note: (ContainerNetwork) -> ResourceTable.Note? = { ResourceTable.Note($0.state.capitalized) }
    @Binding var selectedTab: TabSelection
    @Binding var selectedNetwork: String?
    let emptyStateMessage: String

    var body: some View {
        if networks.isEmpty, placeholders.isEmpty {
            ResourceTable.emptyState(emptyStateMessage, icon: "arrow.down.left.arrow.up.right")
        } else {
            VStack(spacing: 0) {
                ResourceTable.header(["Network", "Address Range", "Gateway", "Status"])

                Divider()

                ForEach(networks) { network in
                    HStack(spacing: 0) {
                        Button {
                            selectedNetwork = network.id
                            selectedTab = .networks
                        } label: {
                            HStack {
                                SwiftUI.Image(systemName: "arrow.down.left.arrow.up.right")
                                    .foregroundStyle(.green)
                                Text(network.id)
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Text(network.status.address ?? "N/A")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(network.status.gateway ?? "N/A")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ResourceTable.statusCell(note(network))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if network.id != networks.last?.id || !placeholders.isEmpty {
                        Divider()
                            .padding(.leading, 12)
                    }
                }

                ForEach(placeholders) { placeholder in
                    HStack(spacing: 0) {
                        HStack {
                            SwiftUI.Image(systemName: "arrow.down.left.arrow.up.right")
                                .foregroundStyle(.tertiary)
                            Text(placeholder.name)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ResourceTable.absentCell()
                        ResourceTable.absentCell()
                        ResourceTable.statusCell(placeholder.note)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if placeholder.id != placeholders.last?.id {
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
