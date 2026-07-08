import SwiftUI

struct MainInterfaceView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @Binding var selectedContainers: Set<String>
    @Binding var selectedImage: String?
    @Binding var selectedMount: String?
    @Binding var selectedMachine: String?
    @Binding var selectedModel: String?
    @Binding var selectedSandbox: String?
    @Binding var selectedDNSDomain: String?
    @Binding var selectedNetwork: String?
    @Binding var lastSelectedContainer: String?
    @Binding var lastSelectedImage: String?
    @Binding var lastSelectedMount: String?
    @Binding var lastSelectedMachine: String?
    @Binding var lastSelectedDNSDomain: String?
    @Binding var lastSelectedNetwork: String?
    @Binding var lastSelectedImageTab: String
    @Binding var lastSelectedMountTab: String
    @Binding var searchText: String
    @Binding var showOnlyRunning: Bool
    @Binding var showOnlyImagesInUse: Bool
    @Binding var showOnlyMountsInUse: Bool
    @Binding var showImageSearch: Bool
    @Binding var showAddDNSDomainSheet: Bool
    @Binding var showAddNetworkSheet: Bool
    @Binding var showAddMachineSheet: Bool
    @Binding var showingItemNavigatorPopover: Bool
    @FocusState var listFocusedTab: TabSelection?
    let windowTitle: String

    // Computed properties
    private var currentResourceTitle: String {
        switch selectedTab {
        case .containers:
            if let selectedContainer = selectedContainer {
                return selectedContainer
            }
            return ""
        case .images:
            if let selectedImage = selectedImage {
                // Extract image name from reference for cleaner display
                let components = selectedImage.split(separator: "/")
                if let lastComponent = components.last {
                    return String(lastComponent.split(separator: ":").first ?? lastComponent)
                }
                return selectedImage
            }
            return ""
        case .mounts:
            if let selectedMount = selectedMount,
               let mount = containerListService.allMounts.first(where: { $0.id == selectedMount }) {
                return URL(fileURLWithPath: mount.mount.source).lastPathComponent
            }
            return ""
        case .dns:
            if let selectedDNSDomain = selectedDNSDomain {
                return selectedDNSDomain
            }
            return ""
        case .networks:
            if let selectedNetwork = selectedNetwork {
                return selectedNetwork
            }
            return ""
        case .machines:
            return selectedMachine ?? ""
        case .registries:
            return ""
        case .systemLogs:
            return ""
        case .dashboard:
            return ""
        case .models:
            return ""
        case .sandboxes:
            return ""
        }
    }

    // Get current container for title bar controls
    private var currentContainer: Container? {
        guard selectedTab == .containers, let selectedContainer = selectedContainer else { return nil }
        return containerListService.containers.first { $0.configuration.id == selectedContainer }
    }

    // Get current mount for title bar display
    private var currentMount: ContainerMount? {
        guard selectedTab == .mounts, let selectedMount = selectedMount else { return nil }
        return containerListService.allMounts.first { $0.id == selectedMount }
    }

    var body: some View {
        ThreeColumnLayout(
            selectedTab: $selectedTab,
            selectedContainer: $selectedContainer,
            selectedContainers: $selectedContainers,
            selectedImage: $selectedImage,
            selectedMount: $selectedMount,
            selectedMachine: $selectedMachine,
            selectedModel: $selectedModel,
            selectedSandbox: $selectedSandbox,
            selectedDNSDomain: $selectedDNSDomain,
            selectedNetwork: $selectedNetwork,
            lastSelectedContainer: $lastSelectedContainer,
            lastSelectedImage: $lastSelectedImage,
            lastSelectedMount: $lastSelectedMount,
            lastSelectedMachine: $lastSelectedMachine,
            lastSelectedDNSDomain: $lastSelectedDNSDomain,
            lastSelectedNetwork: $lastSelectedNetwork,
            lastSelectedImageTab: $lastSelectedImageTab,
            lastSelectedMountTab: $lastSelectedMountTab,
            searchText: $searchText,
            showOnlyRunning: $showOnlyRunning,
            showOnlyImagesInUse: $showOnlyImagesInUse,
            showOnlyMountsInUse: $showOnlyMountsInUse,
            showImageSearch: $showImageSearch,
            showAddDNSDomainSheet: $showAddDNSDomainSheet,
            showAddNetworkSheet: $showAddNetworkSheet,
            showAddMachineSheet: $showAddMachineSheet,
            showingItemNavigatorPopover: $showingItemNavigatorPopover,
            listFocusedTab: _listFocusedTab,
            windowTitle: windowTitle
        )
    }
}
