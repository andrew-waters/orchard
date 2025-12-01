import SwiftUI

// MARK: - Reusable Detail View Button Component

struct DetailViewButton: View {
    let icon: String
    let accessibilityText: String
    let action: () -> Void
    let isDisabled: Bool
    let isLoading: Bool
    let style: ButtonStyle

    init(
        icon: String,
        accessibilityText: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        style: ButtonStyle = .icon
    ) {
        self.icon = icon
        self.accessibilityText = accessibilityText
        self.action = action
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.style = style
    }

    @State private var isRotating: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: isLoading ? "arrow.2.circlepath" : icon)
                    .font(.system(size: style.iconSize, weight: style.iconWeight))
                    .foregroundColor(buttonColor)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))
                    .animation(
                        isLoading
                            ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                        value: isRotating
                    )

                if case .textButton(let text) = style {
                    Text(isLoading ? "Loading..." : text)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding(style.padding)
        }
        .let { button in
            style.applyButtonStyle(button)
        }
        .disabled(isDisabled || isLoading)
        .help(isLoading ? "Loading..." : accessibilityText)
        .onHover { hovering in
            if hovering {
                let cursor: NSCursor = (isDisabled || isLoading) ? .arrow : .pointingHand
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            isRotating = isLoading
        }
        .onChange(of: isLoading) {
            isRotating = isLoading
        }
    }

    private var buttonColor: Color {
        if isLoading {
            return .white
        } else if isDisabled {
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
        case textButton(String)
        case textButtonProminent(String)
        case textButtonDestructive(String)

        var iconSize: CGFloat {
            switch self {
            case .icon, .iconProminent, .iconDestructive:
                return 16
            case .textButton, .textButtonProminent, .textButtonDestructive:
                return 14
            }
        }

        var iconWeight: Font.Weight {
            switch self {
            case .icon, .iconProminent, .iconDestructive:
                return .medium
            case .textButton, .textButtonProminent, .textButtonDestructive:
                return .medium
            }
        }

        var defaultColor: Color {
            switch self {
            case .icon, .iconProminent, .textButton, .textButtonProminent:
                return .gray
            case .iconDestructive, .textButtonDestructive:
                return .red
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .icon, .iconProminent, .iconDestructive:
                return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            case .textButton, .textButtonProminent, .textButtonDestructive:
                return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }

        @ViewBuilder
        func applyButtonStyle<Content: View>(_ content: Content) -> some View {
            switch self {
            case .icon, .iconDestructive:
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
    // Start/Play button
    static func start(action: @escaping () -> Void, isLoading: Bool = false) -> DetailViewButton {
        DetailViewButton(
            icon: "play.fill",
            accessibilityText: "Start",
            action: action,
            isLoading: isLoading,
            style: .icon
        )
    }

    // Stop button
    static func stop(action: @escaping () -> Void, isLoading: Bool = false) -> DetailViewButton {
        DetailViewButton(
            icon: "stop.fill",
            accessibilityText: "Stop",
            action: action,
            isLoading: isLoading,
            style: .icon
        )
    }

    // Remove/Delete button
    static func remove(action: @escaping () -> Void, isDisabled: Bool = false, isLoading: Bool = false) -> DetailViewButton {
        DetailViewButton(
            icon: "trash.fill",
            accessibilityText: "Remove",
            action: action,
            isDisabled: isDisabled,
            isLoading: isLoading,
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
            style: .icon
        )
    }

    // Run Container button (for images)
    static func runContainer(action: @escaping () -> Void, isLoading: Bool = false) -> DetailViewButton {
        DetailViewButton(
            icon: "play.circle.fill",
            accessibilityText: "Run Container",
            action: action,
            isLoading: isLoading,
            style: .textButtonProminent("Run Container")
        )
    }

    // Delete button (for images)
    static func delete(action: @escaping () -> Void, isDisabled: Bool = false, isLoading: Bool = false) -> DetailViewButton {
        DetailViewButton(
            icon: "trash",
            accessibilityText: "Delete",
            action: action,
            isDisabled: isDisabled,
            isLoading: isLoading,
            style: .textButtonDestructive(isLoading ? "Deleting..." : "Delete")
        )
    }
}

// MARK: - View Extension for conditional application

extension View {
    func `let`<T>(_ transform: (Self) -> T) -> T {
        transform(self)
    }
}
