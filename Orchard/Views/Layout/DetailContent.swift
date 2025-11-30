import SwiftUI

struct DetailContentView: View {
    @EnvironmentObject var containerService: ContainerService
    let selectedTab: TabSelection
    let selectedContainer: String?
    let selectedImage: String?
    let selectedMount: String?
    let selectedDNSDomain: String?
    let selectedNetwork: String?
    let isInIntentionalSettingsMode: Bool
    @Binding var lastSelectedContainerTab: String
    @Binding var lastSelectedImageTab: String
    @Binding var lastSelectedMountTab: String
    @Binding var selectedTabBinding: TabSelection
    @Binding var selectedContainerBinding: String?

    var body: some View {
        // Check if we're in settings mode (no selections)
        let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil && selectedNetwork == nil

        if isInIntentionalSettingsMode || (isSettingsMode && (selectedTab == .containers || selectedTab == .images || selectedTab == .mounts)) {
            SettingsDetailView()
        } else {
            switch selectedTab {
            case .containers:
                containerDetailView
            case .images:
                imageDetailView
            case .mounts:
                mountDetailView
            case .dns:
                if let selectedDNSDomain = selectedDNSDomain {
                    DNSDetailView(
                        domain: selectedDNSDomain,
                        selectedTab: $selectedTabBinding,
                        selectedContainer: $selectedContainerBinding
                    )
                } else {
                    Text("Select a DNS domain")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .networks:
                if let selectedNetwork = selectedNetwork {
                    NetworkDetailView(
                        networkId: selectedNetwork,
                        selectedTab: $selectedTabBinding,
                        selectedContainer: $selectedContainerBinding
                    )
                } else {
                    Text("Select a network")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .registries:
                RegistriesDetailView()
            case .systemLogs:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var containerDetailView: some View {
        ForEach(containerService.containers, id: \.configuration.id) { container in
            if selectedContainer == container.configuration.id {
                ContainerDetailView(
                    container: container,
                    initialSelectedTab: lastSelectedContainerTab,
                    onTabChanged: { newTab in
                        lastSelectedContainerTab = newTab
                    }
                )
                .environmentObject(containerService)
            }
        }
    }

    @ViewBuilder
    private var imageDetailView: some View {
        ForEach(containerService.images, id: \.reference) { image in
            if selectedImage == image.reference {
                ContainerImageDetailView(
                    image: image,
                    initialSelectedTab: lastSelectedImageTab,
                    onTabChanged: { newTab in
                        lastSelectedImageTab = newTab
                    }
                )
                .environmentObject(containerService)
            }
        }
    }

    @ViewBuilder
    private var mountDetailView: some View {
        ForEach(containerService.allMounts, id: \.id) { mount in
            if selectedMount == mount.id {
                MountDetailView(
                    mount: mount,
                    initialSelectedTab: lastSelectedMountTab,
                    onTabChanged: { newTab in
                        lastSelectedMountTab = newTab
                    }
                )
                .environmentObject(containerService)
            }
        }
    }
}
