import SwiftUI

struct ContainersListView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @Environment(\.openWindow) private var openWindow
    @Binding var selectedContainer: String?
    @Binding var selectedContainers: Set<String>
    @Binding var lastSelectedContainer: String?
    @Binding var searchText: String
    @Binding var showOnlyRunning: Bool
    @AppStorage("containerSortBy") private var sortBy: ContainerSortOption = .name
    @AppStorage("containerSortAscending") private var sortAscending: Bool = true
    @AppStorage("containerRunningFirst") private var runningFirst: Bool = true
    @AppStorage("containerGroupLabelKey") private var groupLabelKey: String = ""
    @State private var collapsedGroups: Set<String> = []
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            // Container list
            List(selection: $selectedContainers) {
                if groupLabelKey.isEmpty {
                    ForEach(filteredContainers, id: \.configuration.id) { container in
                        containerRow(for: container)
                    }
                } else {
                    ForEach(labelGroups, id: \.id) { group in
                        Section {
                            if !collapsedGroups.contains(group.id) {
                                ForEach(group.containers, id: \.configuration.id) { container in
                                    containerRow(for: container)
                                }
                            }
                        } header: {
                            groupHeader(for: group)
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .background(
                Button(action: selectAllContainers) {
                    EmptyView()
                }
                .keyboardShortcut("a", modifiers: .command)
            )
            .animation(.easeInOut(duration: 0.3), value: containerListService.containers)
            .focused($listFocusedTab, equals: .containers)
            .onChange(of: selectedContainer) { _, newValue in
                lastSelectedContainer = newValue
            }
        }
    }

    private func containerRow(for container: Container) -> some View {
        ListItemRow(
            icon: "cube",
            iconColor: container.status.lowercased() == "running" ? .green : .secondary,
            primaryText: container.configuration.id,
            secondaryLeftText: networkAddress(for: container) ?? "-",
            secondaryRightText: hostname(for: container),
            isSelected: selectedContainers.contains(container.configuration.id),
            showSandboxBadge: container.isSandbox,
            pluginBadge: container.pluginBadgeText
        )
        .contextMenu {
            contextMenu(for: container)
        }
        .tag(container.configuration.id)
    }

    // MARK: - Label grouping

    private struct LabelGroup {
        /// Identity separate from the display name: a label whose value is
        /// literally "No label" must not merge with the fallback bucket.
        let id: String
        let name: String
        let containers: [Container]
    }

    /// The heading for containers missing the grouping label. Chosen to sort
    /// after typical label values and read clearly as a fallback bucket.
    private static let ungroupedName = "No label"

    private var labelGroups: [LabelGroup] {
        let key = groupLabelKey
        var byValue: [String: [Container]] = [:]
        var ungrouped: [Container] = []
        for container in filteredContainers {
            if let value = container.configuration.labels[key], !value.isEmpty {
                byValue[value, default: []].append(container)
            } else {
                ungrouped.append(container)
            }
        }
        var groups = byValue.keys.sorted().map {
            LabelGroup(id: "value:\($0)", name: $0, containers: byValue[$0]!)
        }
        if !ungrouped.isEmpty {
            groups.append(LabelGroup(id: "ungrouped", name: Self.ungroupedName, containers: ungrouped))
        }
        return groups
    }

    private func groupHeader(for group: LabelGroup) -> some View {
        let collapsed = collapsedGroups.contains(group.id)
        let stopped = group.containers.filter { $0.status.lowercased() != "running" }
        let running = group.containers.filter { $0.status.lowercased() == "running" }

        return HStack(spacing: 6) {
            Button {
                if collapsed {
                    collapsedGroups.remove(group.id)
                } else {
                    collapsedGroups.insert(group.id)
                }
            } label: {
                HStack(spacing: 6) {
                    SwiftUI.Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(group.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("\(group.containers.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button("Start All (\(stopped.count))") {
                    let ids = stopped.map { $0.configuration.id }
                    Task {
                        for id in ids {
                            await containerListService.startContainer(id)
                        }
                    }
                }
                .disabled(stopped.isEmpty)

                Button("Stop All (\(running.count))") {
                    let ids = running.map { $0.configuration.id }
                    Task {
                        for id in ids {
                            await containerListService.stopContainer(id)
                        }
                    }
                }
                .disabled(running.isEmpty)
            } label: {
                SwiftUI.Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("Group actions")
        }
        .padding(.vertical, 2)
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
        let targetContainers = containerListService.containers.filter { targetIds.contains($0.configuration.id) }
        let anyRunning = targetContainers.contains { $0.status.lowercased() == "running" }
        let anyStopped = targetContainers.contains { $0.status.lowercased() != "running" }

        if anyRunning {
            Button(multiple ? "Stop \(targetIds.count) Containers" : "Stop Container") {
                Task {
                    for id in targetIds {
                        await containerListService.stopContainer(id)
                    }
                }
            }
            Button(multiple ? "Force Stop \(targetIds.count) Containers" : "Force Stop", role: .destructive) {
                Task {
                    for id in targetIds {
                        await containerListService.forceStopContainer(id)
                    }
                }
            }
        }
        if anyStopped {
            Button(multiple ? "Start \(targetIds.count) Containers" : "Start Container") {
                Task {
                    for id in targetIds {
                        await containerListService.startContainer(id)
                    }
                }
            }
        }

        if !multiple {
            Button("View in Log Viewer") {
                openWindow(id: "logs", value: LogTarget.container(targetIds.first ?? ""))
            }
            Button("Export Filesystem…") {
                ContainerExportFlow.run(containerId: container.configuration.id, service: containerListService)
            }
            .disabled(containerListService.exportingContainers.contains(container.configuration.id))
        }

        Divider()

        Button(multiple ? "Remove \(targetIds.count) Containers" : "Remove Container", role: .destructive) {
            Task {
                await containerListService.removeContainers(targetIds)
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

    private func selectAllContainers() {
        selectedContainers = Set(filteredContainers.map { $0.configuration.id })
    }

    private var filteredContainers: [Container] {
        var filtered = containerListService.containers

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
}
