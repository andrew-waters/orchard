import SwiftUI

struct ContainersListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Environment(\.openWindow) private var openWindow
    @Binding var selectedContainer: String?
    @Binding var selectedContainers: Set<String>
    @Binding var lastSelectedContainer: String?
    @Binding var searchText: String
    @Binding var showOnlyRunning: Bool
    @AppStorage("containerSortBy") private var sortBy: ContainerSortOption = .name
    @AppStorage("containerSortAscending") private var sortAscending: Bool = true
    @AppStorage("containerRunningFirst") private var runningFirst: Bool = true
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            // Container list
            List(selection: $selectedContainers) {
                ForEach(filteredContainers, id: \.configuration.id) { container in
                    ListItemRow(
                        icon: "cube",
                        iconColor: container.status.lowercased() == "running" ? .green : .secondary,
                        primaryText: container.configuration.id,
                        secondaryLeftText: networkAddress(for: container) ?? "-",
                        secondaryRightText: hostname(for: container),
                        isSelected: selectedContainers.contains(container.configuration.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleRowTap(id: container.configuration.id)
                    }
                    .contextMenu {
                        contextMenu(for: container)
                    }
                    .tag(container.configuration.id)
                }
            }
            .listStyle(PlainListStyle())
            .background(
                Button(action: selectAllContainers) {
                    EmptyView()
                }
                .keyboardShortcut("a", modifiers: .command)
            )
            .animation(.easeInOut(duration: 0.3), value: containerService.containers)
            .focused($listFocusedTab, equals: .containers)
            .onChange(of: selectedContainer) { _, newValue in
                lastSelectedContainer = newValue
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for container: Container) -> some View {
        // If the right-clicked container is part of a multi-selection, the actions apply to the whole set.
        let targetIds: [String] = {
            if selectedContainers.count > 1 && selectedContainers.contains(container.configuration.id) {
                return Array(selectedContainers)
            }
            return [container.configuration.id]
        }()
        let multiple = targetIds.count > 1
        let targetContainers = containerService.containers.filter { targetIds.contains($0.configuration.id) }
        let anyRunning = targetContainers.contains { $0.status.lowercased() == "running" }
        let anyStopped = targetContainers.contains { $0.status.lowercased() != "running" }

        if anyRunning {
            Button(multiple ? "Stop \(targetIds.count) Containers" : "Stop Container") {
                Task {
                    for id in targetIds {
                        await containerService.stopContainer(id)
                    }
                }
            }
            Button(multiple ? "Force Stop \(targetIds.count) Containers" : "Force Stop", role: .destructive) {
                Task {
                    for id in targetIds {
                        await containerService.forceStopContainer(id)
                    }
                }
            }
        }
        if anyStopped {
            Button(multiple ? "Start \(targetIds.count) Containers" : "Start Container") {
                Task {
                    for id in targetIds {
                        await containerService.startContainer(id)
                    }
                }
            }
        }

        if !multiple {
            Button("View in Log Viewer") {
                openWindow(id: "logs")
            }
        }

        Divider()

        Button(multiple ? "Remove \(targetIds.count) Containers" : "Remove Container", role: .destructive) {
            Task {
                await containerService.removeContainers(targetIds)
            }
        }
    }

    private func networkAddress(for container: Container) -> String? {
        if let firstNetwork = container.networks.first {
            return firstNetwork.address
        }
        return nil
    }

    private func hostname(for container: Container) -> String? {
        guard !container.networks.isEmpty else { return nil }
        let hostname = container.networks.first?.hostname ?? ""
        return hostname.hasSuffix(".") ? String(hostname.dropLast()) : hostname
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
                    || (hostname(for: container)?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Apply sort
        let ascending = sortAscending
        switch sortBy {
        case .name:
            filtered.sort {
                let result = $0.configuration.id.localizedCaseInsensitiveCompare($1.configuration.id)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        case .status:
            filtered.sort { ascending ? $0.status < $1.status : $0.status > $1.status }
        case .image:
            filtered.sort { ascending ? $0.configuration.image.reference < $1.configuration.image.reference : $0.configuration.image.reference > $1.configuration.image.reference }
        }

        // Float running containers to the top (stable partition)
        if runningFirst {
            let running = filtered.filter { $0.status.lowercased() == "running" }
            let notRunning = filtered.filter { $0.status.lowercased() != "running" }
            filtered = running + notRunning
        }

        return filtered
    }

    private func handleRowTap(id: String) {
        let orderedIds = filteredContainers.map { $0.configuration.id }
        SelectionHandler.handleSelection(
            clickedId: id,
            orderedIds: orderedIds,
            selectedSet: &selectedContainers,
            lastSelectedId: &lastSelectedContainer
        )
    }

    private func selectAllContainers() {
        let orderedIds = filteredContainers.map { $0.configuration.id }
        selectedContainers = Set(orderedIds)
    }
}
