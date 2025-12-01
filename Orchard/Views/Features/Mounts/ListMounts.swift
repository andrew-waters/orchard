import SwiftUI

struct MountsListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedMount: String?
    @Binding var lastSelectedMount: String?
    @Binding var searchText: String
    @Binding var showOnlyMountsInUse: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            // Mounts list
            List(selection: $selectedMount) {
                ForEach(filteredMounts, id: \.id) { mount in
                    MountRow(mount: mount)
                        .tag(mount.id)
                }
            }
            .listStyle(PlainListStyle())
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
}
