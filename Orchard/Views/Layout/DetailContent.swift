import SwiftUI

struct DetailContentView: View {
    @EnvironmentObject var containerService: ContainerService
    let selectedTab: TabSelection
    let selectedContainer: String?
    let selectedContainers: Set<String>
    let selectedImage: String?
    let selectedImages: Set<String>
    let selectedMount: String?
    let selectedMounts: Set<String>
    let selectedDNSDomain: String?
    let selectedDNSDomains: Set<String>
    let selectedNetwork: String?
    let selectedNetworks: Set<String>
    let isInIntentionalConfigurationMode: Bool
    @Binding var lastSelectedContainerTab: String
    @Binding var selectedTabBinding: TabSelection
    @Binding var selectedContainerBinding: String?
    @Binding var selectedContainersBinding: Set<String>
    @Binding var selectedImagesBinding: Set<String>
    @Binding var selectedMountsBinding: Set<String>
    @Binding var selectedDNSDomainsBinding: Set<String>
    @Binding var selectedNetworksBinding: Set<String>
    @Binding var selectedNetworkBinding: String?

    var body: some View {
        switch selectedTab {
        case .containers:
            containerDetailView
        case .images:
            imageDetailView
        case .mounts:
            mountDetailView
        case .dns:
            if selectedDNSDomains.count > 1 {
                MultiDNSCardsView(
                    dnsIds: selectedDNSDomains,
                    selectedDNSDomainsBinding: $selectedDNSDomainsBinding
                )
                .environmentObject(containerService)
            } else if let selectedDNSDomain = selectedDNSDomain {
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
            if selectedNetworks.count > 1 {
                MultiNetworkCardsView(
                    networkIds: selectedNetworks,
                    selectedNetworksBinding: $selectedNetworksBinding
                )
                .environmentObject(containerService)
            } else if let selectedNetwork = selectedNetwork {
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
            VStack {
                Text("System Logs")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Coming Soon")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stats:
            StatsView(
                selectedTab: $selectedTabBinding,
                selectedContainer: $selectedContainerBinding
            )
        case .configuration:
            ConfigurationDetailView()
        }
    }

    @ViewBuilder
    private var containerDetailView: some View {
        if selectedContainers.count > 1 {
            MultiContainerCardsView(
                containerIds: selectedContainers,
                selectedContainersBinding: $selectedContainersBinding
            )
            .environmentObject(containerService)
        } else {
            ForEach(containerService.containers, id: \.configuration.id) { container in
                if selectedContainer == container.configuration.id {
                    ContainerDetailView(
                        container: container,
                        initialSelectedTab: lastSelectedContainerTab,
                        onTabChanged: { newTab in
                            lastSelectedContainerTab = newTab
                        },
                        selectedTabBinding: $selectedTabBinding,
                        selectedNetwork: $selectedNetworkBinding
                    )
                    .environmentObject(containerService)
                }
            }
        }
    }

    @ViewBuilder
    private var imageDetailView: some View {
        if selectedImages.count > 1 {
            MultiImageCardsView(
                imageIds: selectedImages,
                selectedImagesBinding: $selectedImagesBinding
            )
            .environmentObject(containerService)
        } else {
            ForEach(containerService.images, id: \.reference) { image in
                if selectedImage == image.reference {
                    ContainerImageDetailView(
                        image: image,
                        selectedTab: $selectedTabBinding,
                        selectedContainer: $selectedContainerBinding
                    )
                    .environmentObject(containerService)
                }
            }
        }
    }

    @ViewBuilder
    private var mountDetailView: some View {
        if selectedMounts.count > 1 {
            MultiMountCardsView(
                mountIds: selectedMounts,
                selectedMountsBinding: $selectedMountsBinding
            )
            .environmentObject(containerService)
        } else {
            ForEach(containerService.allMounts, id: \.id) { mount in
                if selectedMount == mount.id {
                    MountDetailView(
                        mount: mount,
                        selectedTab: $selectedTabBinding,
                        selectedContainer: $selectedContainerBinding
                    )
                    .environmentObject(containerService)
                }
            }
        }
    }
}
