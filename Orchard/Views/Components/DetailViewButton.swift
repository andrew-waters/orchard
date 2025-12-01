import SwiftUI

// MARK: - Reusable Detail View Button Component

struct DetailViewButton: View {
    let icon: String
    let accessibilityText: String
    let action: () -> Void
    let isDisabled: Bool
    let style: ButtonStyle

    init(
        icon: String,
        accessibilityText: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false,
        style: ButtonStyle = .icon
    ) {
        self.icon = icon
        self.accessibilityText = accessibilityText
        self.action = action
        self.isDisabled = isDisabled
        self.style = style
    }

    @State private var isRotating: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: icon)
                    .font(.system(size: style.iconSize, weight: style.iconWeight))
                    .foregroundColor(buttonColor)

                if case .textButton(let text) = style {
                    Text(text)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding(style.padding)
        }
        .let { button in
            style.applyButtonStyle(button)
        }
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
            return .gray.opacity(0.5)
        } else {
            return style.defaultColor
        }
    }
}

// MARK: - Button Styles

extension DetailViewButton {
    enum ButtonStyle {
        case icon
        case iconProminent
        case iconDestructive
        case folderButton
        case playButton
        case textButton(String)
        case textButtonProminent(String)
        case textButtonDestructive(String)

        var iconSize: CGFloat {
            switch self {
            case .icon, .iconProminent:
                return 16  // Container start/stop buttons
            case .iconDestructive:
                return 16  // Container remove/trash buttons
            case .folderButton:
                return 16  // Mount folder button
            case .playButton:
                return 16  // Image play button
            case .textButton, .textButtonProminent, .textButtonDestructive:
                return 16
            }
        }

        var iconWeight: Font.Weight {
            switch self {
            case .icon, .iconProminent, .iconDestructive, .folderButton, .playButton:
                return .medium
            case .textButton, .textButtonProminent, .textButtonDestructive:
                return .medium
            }
        }

        var defaultColor: Color {
            switch self {
            case .icon, .iconProminent, .folderButton, .playButton, .textButton, .textButtonProminent:
                return .gray
            case .iconDestructive, .textButtonDestructive:
                return .red
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .icon, .iconProminent, .iconDestructive, .folderButton, .playButton:
                return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            case .textButton, .textButtonProminent, .textButtonDestructive:
                return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }

        @ViewBuilder
        func applyButtonStyle<Content: View>(_ content: Content) -> some View {
            switch self {
            case .icon, .iconDestructive, .folderButton, .playButton:
                content.buttonStyle(.plain)
            case .iconProminent, .textButtonProminent:
                content.buttonStyle(.borderedProminent)
            case .textButton, .textButtonDestructive:
                content.buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Convenience Initializers

extension DetailViewButton {
    // Remove/Delete button
    static func remove(action: @escaping () -> Void, isDisabled: Bool = false, isLoading: Bool = false) -> DetailViewButton {
        DetailViewButton(
            icon: "trash.fill",
            accessibilityText: "Remove",
            action: action,
            isDisabled: isDisabled,
            style: .iconDestructive
        )
    }

    // Terminal button
    static func terminal(action: @escaping () -> Void) -> DetailViewButton {
        DetailViewButton(
            icon: "terminal",
            accessibilityText: "Open Terminal",
            action: action,
            style: .icon
        )
    }

    // Folder/Finder button
    static func openInFinder(action: @escaping () -> Void) -> DetailViewButton {
        DetailViewButton(
            icon: "folder",
            accessibilityText: "Open in Finder",
            action: action,
            style: .folderButton
        )
    }
}

// MARK: - View Extension for conditional application

extension View {
    func `let`<T>(_ transform: (Self) -> T) -> T {
        transform(self)
    }
}
