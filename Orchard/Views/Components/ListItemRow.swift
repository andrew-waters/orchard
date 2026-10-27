import SwiftUI

struct ListItemRow: View {
    /// The height of a row with a secondary line in a plain `List`, cell insets included.
    ///
    /// A list given this as its minimum row height lays a newly inserted row out at its real
    /// height. Without it, a row inserted at the top of a plain `List` (an `NSTableView`
    /// underneath) can keep the default minimum of about 24 points: the row is squashed and
    /// the next one is drawn over it until the list is rebuilt. Only for lists whose rows all
    /// have a secondary line, or one-line rows would grow to match.
    static let twoLineHeight: CGFloat = 56

    let icon: String
    let iconColor: Color
    let primaryText: String
    let secondaryLeftText: String?
    let secondaryRightText: String?
    let isSelected: Bool
    /// When true, a small capsule marks the row as a sandbox (an isolated workload).
    let showSandboxBadge: Bool
    /// The app managing a sandbox Orchard didn't make (e.g. "Gannin session").
    let ownerBadge: String?
    /// Plugin + role capsule for plugin-owned containers (e.g. "k8s · control-plane").
    let pluginBadge: String?
    /// A capsule for something the row is not doing as asked, such as a compose project with
    /// keys Orchard will not honour. Orange rather than accent-coloured: it is a caveat, not a
    /// label.
    let warningBadge: String?

    init(
        icon: String,
        iconColor: Color,
        primaryText: String,
        secondaryLeftText: String? = nil,
        secondaryRightText: String? = nil,
        isSelected: Bool = false,
        showSandboxBadge: Bool = false,
        ownerBadge: String? = nil,
        pluginBadge: String? = nil,
        warningBadge: String? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.primaryText = primaryText
        self.secondaryLeftText = secondaryLeftText
        self.secondaryRightText = secondaryRightText
        self.isSelected = isSelected
        self.showSandboxBadge = showSandboxBadge
        self.ownerBadge = ownerBadge
        self.pluginBadge = pluginBadge
        self.warningBadge = warningBadge
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            SwiftUI.Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(iconColor)
                .frame(width: 20, height: 20)
                .opacity(isSelected ? 1.0 : 0.7)

            // Text content
            VStack(alignment: .leading, spacing: 6) {
                // Primary text
                HStack(spacing: 5) {
                    Text(primaryText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if showSandboxBadge {
                        Text("sandbox")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            .lineLimit(1)
                            .help("Sandbox - an isolated workload")
                    }
                    if let ownerBadge {
                        Text(ownerBadge)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.purple.opacity(0.14)))
                            .lineLimit(1)
                            .help("Managed by another app")
                    }
                    if let pluginBadge {
                        Text(pluginBadge)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            .lineLimit(1)
                            .help("Managed by a container plugin")
                    }
                    if let warningBadge {
                        Text(warningBadge)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                            .lineLimit(1)
                            .help("This project asks for something Orchard will not do")
                    }
                }

                // Secondary text row
                if secondaryLeftText != nil || secondaryRightText != nil {
                    HStack {
                        if let secondaryLeft = secondaryLeftText {
                            Text(secondaryLeft)
                                .font(.system(size: 10, weight: .regular))
                                .fontDesign(.monospaced)
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let secondaryRight = secondaryRightText {
                            Text(secondaryRight)
                                .font(.system(size: 10, weight: .regular))
                                .fontDesign(.monospaced)
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 4) {
        ListItemRow(
            icon: "cube",
            iconColor: .blue,
            primaryText: "buildkit",
            secondaryLeftText: "192.168.64.23",
            secondaryRightText: "Running",
            isSelected: true
        )

        ListItemRow(
            icon: "cube",
            iconColor: .gray,
            primaryText: "kafka",
            secondaryLeftText: "Not running"
        )

        ListItemRow(
            icon: "cube.transparent",
            iconColor: .purple,
            primaryText: "redis",
            secondaryLeftText: "latest",
            secondaryRightText: "529 bytes"
        )

        ListItemRow(
            icon: "externaldrive",
            iconColor: .orange,
            primaryText: "/ → run",
            secondaryLeftText: "provisioning → provisioning"
        )
    }
    .padding()
}
