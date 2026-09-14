import SwiftUI

struct ContainerTable: View {
    /// A short trailing note on a row: what is happening to it, or why it is not there.
    struct Note: Equatable {
        let text: String
        var isError: Bool = false

        init(_ text: String, isError: Bool = false) {
            self.text = text
            self.isError = isError
        }
    }

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
    /// What is happening to a container right now, if anything.
    var note: (Container) -> Note? = { _ in nil }
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    let emptyStateMessage: String

    /// The trailing column only exists when something has something to say, so every table
    /// that never passes a note keeps exactly the layout it had.
    private var showsNotes: Bool {
        !placeholders.isEmpty || containers.contains { note($0) != nil }
    }

    private static let noteWidth: CGFloat = 150

    var body: some View {
        if containers.isEmpty, placeholders.isEmpty {
            HStack {
                SwiftUI.Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
                Text(emptyStateMessage)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        } else {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Container")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("IP Address")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Hostname")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsNotes {
                        Text("Status")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: Self.noteWidth, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.separatorColor).opacity(0.5))

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

                        if showsNotes {
                            noteCell(note(container))
                        }
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

                        Text("-")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("-")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        noteCell(placeholder.note)
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

    @ViewBuilder
    private func noteCell(_ note: Note?) -> some View {
        Text(note?.text ?? "")
            .font(.caption)
            .foregroundStyle(note?.isError == true ? Color.red : Color.secondary)
            .lineLimit(1)
            .frame(width: Self.noteWidth, alignment: .leading)
    }
}
