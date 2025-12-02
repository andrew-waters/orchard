import SwiftUI

struct ListItemRow: View {
    let icon: String
    let iconColor: Color
    let primaryText: String
    let secondaryLeftText: String?
    let secondaryRightText: String?
    let isSelected: Bool

    init(
        icon: String,
        iconColor: Color,
        primaryText: String,
        secondaryLeftText: String? = nil,
        secondaryRightText: String? = nil,
        isSelected: Bool = false
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.primaryText = primaryText
        self.secondaryLeftText = secondaryLeftText
        self.secondaryRightText = secondaryRightText
        self.isSelected = isSelected
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
                Text(primaryText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

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
