import SwiftUI

struct DetailContentView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    let selectedTab: TabSelection
    let selectedContainer: String?
    let selectedContainers: Set<String>
    let selectedImage: String?
    let selectedMount: String?
    let selectedDNSDomain: String?
    let selectedNetwork: String?
    let isInIntentionalConfigurationMode: Bool
    @Binding var lastSelectedContainerTab: String
    @Binding var selectedTabBinding: TabSelection
    @Binding var selectedContainerBinding: String?
    @Binding var selectedContainersBinding: Set<String>
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
        } else {
            ForEach(containerListService.containers, id: \.configuration.id) { container in
                if selectedContainer == container.configuration.id {
                    ContainerDetailView(
                        container: container,
                        selectedTabBinding: $selectedTabBinding,
                        selectedNetwork: $selectedNetworkBinding
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var imageDetailView: some View {
        ForEach(imageService.images, id: \.reference) { image in
            if selectedImage == image.reference {
                ContainerImageDetailView(
                    image: image,
                    selectedTab: $selectedTabBinding,
                    selectedContainer: $selectedContainerBinding
                )
            }
        }
    }

    @ViewBuilder
    private var mountDetailView: some View {
        ForEach(containerListService.allMounts, id: \.id) { mount in
            if selectedMount == mount.id {
                MountDetailView(
                    mount: mount,
                    selectedTab: $selectedTabBinding,
                    selectedContainer: $selectedContainerBinding
                )
            }
        }
    }
}
