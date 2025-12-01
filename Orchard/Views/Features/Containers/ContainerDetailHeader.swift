import SwiftUI

// MARK: - Container Detail Header
struct ContainerDetailHeader: View {
    let container: Container
    @EnvironmentObject var containerService: ContainerService

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
                ContainerControlButton(
                    container: container,
                    isLoading: containerService.loadingContainers.contains(container.configuration.id),
                    onStart: {
                        Task { @MainActor in
                            await containerService.startContainer(container.configuration.id)
                        }
                    },
                    onStop: {
                        Task { @MainActor in
                            await containerService.stopContainer(container.configuration.id)
                        }
                    }
                )

                if container.status.lowercased() == "running" {
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
                    ContainerRemoveButton(
                        container: container,
                        isLoading: containerService.loadingContainers.contains(container.configuration.id),
                        onRemove: {
                            Task { @MainActor in
                                await containerService.removeContainer(container.configuration.id)
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
    }
}
