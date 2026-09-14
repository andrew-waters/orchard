import SwiftUI

/// The shared look of the resource tables: containers, networks, and whatever comes next.
///
/// It exists so that "the same style" is the same code rather than the same intention. Two
/// tables that merely agree today drift the first time one of them is touched.
enum ResourceTable {
    /// What the status column says for a row.
    struct Note: Equatable {
        let text: String
        var isError: Bool = false

        init(_ text: String, isError: Bool = false) {
            self.text = text
            self.isError = isError
        }
    }

    /// Fixed, and always there. A column that appears when there is something to say and
    /// vanishes when there is not reflows the whole table every time a step of a plan
    /// finishes, which is exactly when someone is trying to read it.
    static let statusWidth: CGFloat = 150

    /// The header row. Every title but the last shares the width evenly; the last is the
    /// status column and is fixed.
    static func header(_ titles: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(titles.dropLast(), id: \.self) { title in
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(titles.last ?? "")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: statusWidth, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.separatorColor).opacity(0.5))
    }

    static func statusCell(_ note: Note?) -> some View {
        Text(note?.text ?? "")
            .font(.caption)
            .foregroundStyle(note?.isError == true ? Color.red : Color.secondary)
            .lineLimit(1)
            .frame(width: statusWidth, alignment: .leading)
    }

    /// A column of a placeholder row: the value is not there to show.
    static func absentCell() -> some View {
        Text("-")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func emptyState(_ message: String, icon: String) -> some View {
        HStack {
            SwiftUI.Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
