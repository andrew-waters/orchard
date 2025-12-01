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
                    DetailViewButton.stop(
                        action: {
                            Task { @MainActor in
                                await containerService.stopContainer(container.configuration.id)
                            }
                        },
                        isLoading: isLoading
                    )
                } else {
                    DetailViewButton.start(
                        action: {
                            Task { @MainActor in
                                await containerService.startContainer(container.configuration.id)
                            }
                        },
                        isLoading: isLoading
                    )
                }

                if isRunning {
                    // Terminal button (keep original menu functionality for now)
                    ContainerTerminalButton(
                        container: container,
                        onOpenTerminal: {
                            containerService.openTerminal(for: container.configuration.id)
                        },
                        onOpenTerminalBash: {
                            containerService.openTerminalWithBash(for: container.configuration.id)
                        }
                    )
                } else {
                    DetailViewButton.remove(
                        action: {
                            Task { @MainActor in
                                await containerService.removeContainer(container.configuration.id)
                            }
                        },
                        isDisabled: isRunning,
                        isLoading: isLoading
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
    }
}
