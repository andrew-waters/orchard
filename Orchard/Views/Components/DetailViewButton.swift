import SwiftUI

// MARK: - Reusable Detail View Button Component

struct DetailViewButton: View {
    let icon: String
    let accessibilityText: String
    let action: () -> Void
    let isDisabled: Bool
    let isLoading: Bool

    init(
        icon: String,
        accessibilityText: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false,
        isLoading: Bool = false
    ) {
        self.icon = icon
        self.accessibilityText = accessibilityText
        self.action = action
        self.isDisabled = isDisabled
        self.isLoading = isLoading
    }

    @State private var glowIntensity: Double = 0.0

    var body: some View {
        Button(action: isLoading ? {} : action) {
            HStack(spacing: 6) {
                SwiftUI.Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(buttonColor)
                    .shadow(
                        color: isLoading ? .blue.opacity(glowIntensity) : .clear,
                        radius: isLoading ? 8 : 0
                    )
                    .scaleEffect(isLoading ? 1.1 : 1.0)
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6))
        }
        .buttonStyle(.plain)
        .help(accessibilityText)
        .disabled(isDisabled || isLoading)
        .onHover { hovering in
            if hovering {
                let cursor: NSCursor = (isDisabled || isLoading) ? .arrow : .pointingHand
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            if isLoading {
                startGlowAnimation()
            }
        }
        .onChange(of: isLoading) { _, newValue in
            if newValue {
                startGlowAnimation()
            } else {
                stopGlowAnimation()
            }
        }
    }

    private var buttonColor: Color {
        if isLoading {
            return .blue
        } else if isDisabled {
            return .primary.opacity(0.5)
        } else {
            return .primary
        }
    }

    private func startGlowAnimation() {
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            glowIntensity = 0.8
        }
    }

    private func stopGlowAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            glowIntensity = 0.0
        }
    }
}
