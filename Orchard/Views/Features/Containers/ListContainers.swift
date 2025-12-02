import SwiftUI

struct ContainersListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedContainer: String?
    @Binding var lastSelectedContainer: String?
    @Binding var searchText: String
    @Binding var showOnlyRunning: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            // Container list
            List(selection: $selectedContainer) {
                ForEach(filteredContainers, id: \.configuration.id) { container in
                    ListItemRow(
                        icon: "cube",
                        iconColor: container.status.lowercased() == "running" ? .green : .gray,
                        primaryText: container.configuration.id,
                        secondaryLeftText: networkAddress(for: container),
                        secondaryRightText: container.status,
                        isSelected: false
                    )
                    .contextMenu {
                        if container.status.lowercased() == "running" {
                            Button("Stop Container") {
                                Task {
                                    await containerService.stopContainer(container.configuration.id)
                                }
                            }
                        } else {
                            Button("Start Container") {
                                Task {
                                    await containerService.startContainer(container.configuration.id)
                                }
                            }
                        }

                        Divider()

                        Button("Remove Container", role: .destructive) {
                            Task {
                                await containerService.removeContainer(container.configuration.id)
                            }
                        }
                    }
                    .tag(container.configuration.id)
                }
            }
            .listStyle(PlainListStyle())
            .animation(.easeInOut(duration: 0.3), value: containerService.containers)
            .focused($listFocusedTab, equals: .containers)
            .onChange(of: selectedContainer) { _, newValue in
                lastSelectedContainer = newValue
            }
        }
    }

    private func networkAddress(for container: Container) -> String? {
        if let firstNetwork = container.networks.first {
            return firstNetwork.address
        }
        return nil
    }

    private var filteredContainers: [Container] {
        var filtered = containerService.containers

        // Apply running filter
        if showOnlyRunning {
            filtered = filtered.filter { $0.status.lowercased() == "running" }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { container in
                container.configuration.id.localizedCaseInsensitiveContains(searchText)
                    || container.status.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }
}
