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
                // Start/Stop button
                if isRunning {
                    DetailViewButton(
                        icon: "stop.circle",
                        accessibilityText: "Stop this container",
                        action: {
                            Task { @MainActor in
                                await containerService.stopContainer(container.configuration.id)
                            }
                        },
                        style: .playButton
                    )
                } else {
                    DetailViewButton(
                        icon: "arrowtriangle.right.circle",
                        accessibilityText: "Start this container",
                        action: {
                            Task { @MainActor in
                                await containerService.startContainer(container.configuration.id)
                            }
                        },
                        style: .playButton
                    )
                }

                if isRunning {
                    DetailViewButton(
                        icon: "terminal",
                        accessibilityText: "Exec into container",
                        action: {
                            Task { @MainActor in
                                await containerService.startContainer(container.configuration.id)
                            }
                        },
                        style: .playButton
                    )

                    // Terminal button (keep original menu functionality for now)
//                    ContainerTerminalButton(
//                        container: container,
//                        onOpenTerminal: {
//                            containerService.openTerminal(for: container.configuration.id)
//                        },
//                        onOpenTerminalBash: {
//                            containerService.openTerminalWithBash(for: container.configuration.id)
//                        }
//                    )
                } else {
                    DetailViewButton(
                        icon: "trash.fill",
                        accessibilityText: "Delete this container",
                        action: {
                            Task { @MainActor in
                                await containerService.removeContainer(container.configuration.id)
                            }
                        },
                        style: .playButton
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
    }
}
