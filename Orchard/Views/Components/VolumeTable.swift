import SwiftUI

/// A compose project's volumes in the same table as its containers and networks (#162), since
/// the same plan creates them.
struct VolumeTable: View {
    struct Row: Identifiable {
        let name: String
        let kind: ComposeProjectVolume.Kind
        /// Whether the volume exists. A row that doesn't is one the next `up` creates, or an
        /// external volume that is missing.
        let exists: Bool
        let size: MeasuredSize?
        let note: ResourceTable.Note?

        var id: String { name }
    }

    let rows: [Row]
    let emptyStateMessage: String

    var body: some View {
        if rows.isEmpty {
            ResourceTable.emptyState(emptyStateMessage, icon: "cylinder")
        } else {
            VStack(spacing: 0) {
                ResourceTable.header(["Volume", "Kind", "Size", "Status"])

                Divider()

                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        nameCell(row)

                        Text(kindText(row.kind))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if row.exists {
                            Text(VolumeFormat.size(row.size))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ResourceTable.absentCell()
                        }

                        ResourceTable.statusCell(row.note)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if row.id != rows.last?.id {
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
    private func nameCell(_ row: Row) -> some View {
        if row.exists {
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("NavigateToVolume"), object: row.name)
            } label: {
                HStack {
                    SwiftUI.Image(systemName: "cylinder")
                        .foregroundStyle(.green)
                    Text(row.name)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                SwiftUI.Image(systemName: "cylinder")
                    .foregroundStyle(.tertiary)
                Text(row.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func kindText(_ kind: ComposeProjectVolume.Kind) -> String {
        switch kind {
        case .named: return "Named"
        case .anonymous: return "Anonymous"
        case .external: return "External"
        }
    }
}
