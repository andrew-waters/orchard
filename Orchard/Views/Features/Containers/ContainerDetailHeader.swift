import SwiftUI

// MARK: - Container Detail Header
struct ContainerDetailHeader: View {
    let container: Container
    @EnvironmentObject var containerService: ContainerService

    private var isLoading: Bool {
        containerService.loadingContainers.contains(container.configuration.id)
    }

    private var isRunning: Bool {
        container.status.lowercased() == "running"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(container.configuration.id)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Primary action button - only show ONE at a time
                if isRunning {
                    // Container is running - show stop button
                    DetailViewButton(
                        icon: "stop.circle",
                        accessibilityText: "Stop this container",
                        action: {
                            Task { @MainActor in
                                await containerService.stopContainer(container.configuration.id)
                            }
                        },
                        isLoading: isLoading
                    )

                    // Terminal buttons - only when running and not loading
                    if !isLoading {
                        DetailViewButton(
                            icon: "terminal",
                            accessibilityText: "Open Terminal (sh)",
                            action: {
                                containerService.openTerminal(for: container.configuration.id)
                            }
                        )

                        DetailViewButton(
                            icon: "terminal.fill",
                            accessibilityText: "Open Terminal (bash)",
                            action: {
                                containerService.openTerminalWithBash(for: container.configuration.id)
                            }
                        )
                    }
                } else {
                    // Container is stopped - show start OR delete button, but never both
                    if isLoading {
                        // If loading, show the start button (most likely action when stopped + loading)
                        DetailViewButton(
                            icon: "arrowtriangle.right.circle",
                            accessibilityText: "Start this container",
                            action: {
                                Task { @MainActor in
                                    await containerService.startContainer(container.configuration.id)
                                }
                            },
                            isLoading: true
                        )
                    } else {
                        // Not loading - show both start and delete buttons
                        DetailViewButton(
                            icon: "arrowtriangle.right.circle",
                            accessibilityText: "Start this container",
                            action: {
                                Task { @MainActor in
                                    await containerService.startContainer(container.configuration.id)
                                }
                            }
                        )

                        DetailViewButton(
                            icon: "trash.fill",
                            accessibilityText: "Delete this container",
                            action: {
                                Task { @MainActor in
                                    await containerService.removeContainer(container.configuration.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
