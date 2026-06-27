import SwiftUI

struct MountsListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedMount: String?
    @Binding var selectedMounts: Set<String>
    @Binding var lastSelectedMount: String?
    @Binding var searchText: String
    @Binding var showOnlyMountsInUse: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            // Mounts list
            List(selection: $selectedMounts) {
                ForEach(filteredMounts, id: \.id) { mount in
                    let targetMounts: [ContainerMount] = {
                        if selectedMounts.count > 1 && selectedMounts.contains(mount.id) {
                            return containerService.allMounts.filter { selectedMounts.contains($0.id) }
                        }
                        return [mount]
                    }()
                    let multiple = targetMounts.count > 1

                    ListItemRow(
                        icon: "externaldrive",
                        iconColor: isMountUsedByRunningContainer(mount) ? .green : .secondary,
                        primaryText: mount.mount.destination,
                        secondaryLeftText: mount.mount.source,
                        isSelected: selectedMounts.contains(mount.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleRowTap(id: mount.id)
                    }
                    .contextMenu {
                        Button(multiple ? "Copy Source Paths" : "Copy Source Path") {
                            let text = targetMounts.map { $0.mount.source }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }

                        Button(multiple ? "Copy Destination Paths" : "Copy Destination Path") {
                            let text = targetMounts.map { $0.mount.destination }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }

                        Divider()

                        Button(multiple ? "Remove \(targetMounts.count) Mounts" : "Remove Mount", role: .destructive) {
                            confirmMountsDeletion(mounts: targetMounts)
                        }
                    }
                    .tag(mount.id)
                }
            }
            .listStyle(PlainListStyle())
            .background(
                Button(action: selectAllMounts) {
                    EmptyView()
                }
                .keyboardShortcut("a", modifiers: .command)
            )
            .animation(.easeInOut(duration: 0.3), value: containerService.allMounts)
            .focused($listFocusedTab, equals: .mounts)
            .onChange(of: selectedMount) { _, newValue in
                lastSelectedMount = newValue
            }


        }
    }

    private var filteredMounts: [ContainerMount] {
        var filtered = containerService.allMounts

        // Apply "in use" filter
        if showOnlyMountsInUse {
            filtered = filtered.filter { mount in
                // Only show mounts used by running containers
                mount.containerIds.contains { containerID in
                    containerService.containers.first { $0.configuration.id == containerID }?.status.lowercased() == "running"
                }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { mount in
                mount.mount.source.localizedCaseInsensitiveContains(searchText)
                    || mount.mount.destination.localizedCaseInsensitiveContains(searchText)
                    || mount.mountType.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    private func isMountUsedByRunningContainer(_ mount: ContainerMount) -> Bool {
        return mount.containerIds.contains { containerID in
            containerService.containers.first { $0.configuration.id == containerID }?.status.lowercased() == "running"
        }
    }

    private func handleRowTap(id: String) {
        let orderedIds = filteredMounts.map { $0.id }
        SelectionHandler.handleSelection(
            clickedId: id,
            orderedIds: orderedIds,
            selectedSet: &selectedMounts,
            lastSelectedId: &lastSelectedMount
        )
    }

    private func selectAllMounts() {
        let orderedIds = filteredMounts.map { $0.id }
        selectedMounts = Set(orderedIds)
    }

    private func confirmMountsDeletion(mounts: [ContainerMount]) {
        let alert = NSAlert()
        alert.messageText = "Remove Mounts"
        alert.informativeText = "Are you sure you want to remove the selected \(mounts.count) mount(s)? The associated containers will be deleted and recreated without these mounts."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await containerService.deleteMounts(mounts)
            }
        }
    }
}
