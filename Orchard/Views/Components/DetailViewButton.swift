import SwiftUI

// MARK: - Reusable Detail View Button Component

struct DetailViewButton: View {
    let icon: String
    let accessibilityText: String
    let action: () -> Void
    let isDisabled: Bool

    init(
        icon: String,
        accessibilityText: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false,
    ) {
        self.icon = icon
        self.accessibilityText = accessibilityText
        self.action = action
        self.isDisabled = isDisabled
    }

    @State private var isRotating: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(buttonColor)
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6))
        }
        .buttonStyle(.plain)
        .help(accessibilityText)
        .onHover { hovering in
            if hovering {
                let cursor: NSCursor = (isDisabled) ? .arrow : .pointingHand
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var buttonColor: Color {
        if isDisabled {
            return .primary.opacity(0.5)
        } else {
            return .primary
        }
    }
}
