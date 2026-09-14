import SwiftUI

struct ContainerTable: View {
    /// The same note the other resource tables use.
    typealias Note = ResourceTable.Note

    /// A row for something that should exist and does not yet, such as a compose service
    /// nothing has created. Shown after the real containers, greyed, so a stack reads as a
    /// whole rather than as the part of it that happens to exist.
    struct Placeholder: Identifiable {
        let name: String
        let note: Note

        var id: String { name }
    }

    let containers: [Container]
    var placeholders: [Placeholder] = []
    /// What the status column says for a row. By default the container's own state; a caller
    /// with something more immediate to report, such as a compose plan mid-run, says that
    /// instead.
    var note: (Container) -> Note? = { Note($0.status.capitalized) }
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    let emptyStateMessage: String

    var body: some View {
        if containers.isEmpty, placeholders.isEmpty {
            ResourceTable.emptyState(emptyStateMessage, icon: "cube.transparent")
        } else {
            VStack(spacing: 0) {
                ResourceTable.header(["Container", "IP Address", "Hostname", "Status"])

                Divider()

                // Container rows
                ForEach(containers, id: \.configuration.id) { container in
                    let containerNetwork = container.networks.first
                    let displayAddress = {
                        guard let address = containerNetwork?.address else { return "N/A" }
                        return address.strippingCIDRSuffix
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
                                let cleanAddress = address.strippingCIDRSuffix
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

                        ResourceTable.statusCell(note(container))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.clear)

                    if container.configuration.id != containers.last?.configuration.id || !placeholders.isEmpty {
                        Divider()
                            .padding(.leading, 12)
                    }
                }

                ForEach(placeholders) { placeholder in
                    HStack(spacing: 0) {
                        HStack {
                            SwiftUI.Image(systemName: "cube")
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
