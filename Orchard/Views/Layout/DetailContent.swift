import SwiftUI

struct DetailContentView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    let selectedTab: TabSelection
    let selectedContainer: String?
    let selectedContainers: Set<String>
    let selectedImage: String?
    let selectedImages: Set<String>
    let selectedMount: String?
    let selectedMounts: Set<String>
    let selectedMachine: String?
    let selectedModel: String?
    let selectedSandbox: String?
    let selectedDNSDomain: String?
    let selectedDNSDomains: Set<String>
    let selectedNetwork: String?
    let selectedNetworks: Set<String>
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
        case .machines:
            if let selectedMachine = selectedMachine {
                MachineDetailView(machineId: selectedMachine)
            } else {
                Text("Select a machine")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        case .dashboard:
            DashboardView(
                selectedTab: $selectedTabBinding,
                selectedContainer: $selectedContainerBinding
            )
        case .models:
            ModelDetailView(selectedModel: selectedModel)
        case .sandboxes:
            SandboxDetailView(selectedSandbox: selectedSandbox)
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
        
        if selectedImages.count > 1 {
            MultiImageCardsView(
                imageIds: selectedImages,
                selectedImagesBinding: $selectedImagesBinding
            )
        } else {
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
    }

    @ViewBuilder
    private var mountDetailView: some View {
        
        if selectedMounts.count > 1 {
            MultiMountCardsView(
                mountIds: selectedMounts,
                selectedMountsBinding: $selectedMountsBinding
            )
        } else {
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
}
