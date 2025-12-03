import SwiftUI

struct MainInterfaceView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @Binding var selectedImage: String?
    @Binding var selectedMount: String?
    @Binding var selectedDNSDomain: String?
    @Binding var selectedNetwork: String?
    @Binding var lastSelectedContainer: String?
    @Binding var lastSelectedImage: String?
    @Binding var lastSelectedMount: String?
    @Binding var lastSelectedDNSDomain: String?
    @Binding var lastSelectedNetwork: String?
    @Binding var lastSelectedContainerTab: String
    @Binding var lastSelectedImageTab: String
    @Binding var lastSelectedMountTab: String
    @Binding var searchText: String
    @Binding var showOnlyRunning: Bool
    @Binding var showOnlyImagesInUse: Bool
    @Binding var showOnlyMountsInUse: Bool
    @Binding var showImageSearch: Bool
    @Binding var showAddDNSDomainSheet: Bool
    @Binding var showAddNetworkSheet: Bool
    @Binding var isInIntentionalConfigurationMode: Bool
    @Binding var showingItemNavigatorPopover: Bool
    @FocusState var listFocusedTab: TabSelection?
    let isWindowFocused: Bool
    let windowTitle: String

    // Computed properties
    private var currentResourceTitle: String {
        // Check if we're in intentional configuration mode first
        if isInIntentionalConfigurationMode {
            return "Configuration"
        }

        // Check if we're in configuration mode (no selections)
        let isConfigurationMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil && selectedNetwork == nil

        // Only show configuration title if we're intentionally in configuration mode, not during initial loading
        if isConfigurationMode && isInIntentionalConfigurationMode {
            return "Configuration"
        }

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
               let mount = containerService.allMounts.first(where: { $0.id == selectedMount }) {
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
        case .registries:
            return ""
        case .systemLogs:
            return ""
        case .stats:
            return ""
        case .configuration:
            return ""
        }
    }

    // Get current container for title bar controls
    private var currentContainer: Container? {
        guard selectedTab == .containers, let selectedContainer = selectedContainer else { return nil }
        return containerService.containers.first { $0.configuration.id == selectedContainer }
    }

    // Get current mount for title bar display
    private var currentMount: ContainerMount? {
        guard selectedTab == .mounts, let selectedMount = selectedMount else { return nil }
        return containerService.allMounts.first { $0.id == selectedMount }
    }

    var body: some View {
        ThreeColumnLayout(
            selectedTab: $selectedTab,
            selectedContainer: $selectedContainer,
            selectedImage: $selectedImage,
            selectedMount: $selectedMount,
            selectedDNSDomain: $selectedDNSDomain,
            selectedNetwork: $selectedNetwork,
            lastSelectedContainer: $lastSelectedContainer,
            lastSelectedImage: $lastSelectedImage,
            lastSelectedMount: $lastSelectedMount,
            lastSelectedDNSDomain: $lastSelectedDNSDomain,
            lastSelectedNetwork: $lastSelectedNetwork,
            lastSelectedContainerTab: $lastSelectedContainerTab,
            lastSelectedImageTab: $lastSelectedImageTab,
            lastSelectedMountTab: $lastSelectedMountTab,
            searchText: $searchText,
            showOnlyRunning: $showOnlyRunning,
            showOnlyImagesInUse: $showOnlyImagesInUse,
            showOnlyMountsInUse: $showOnlyMountsInUse,
            showImageSearch: $showImageSearch,
            showAddDNSDomainSheet: $showAddDNSDomainSheet,
            showAddNetworkSheet: $showAddNetworkSheet,
            isInIntentionalConfigurationMode: $isInIntentionalConfigurationMode,
            showingItemNavigatorPopover: $showingItemNavigatorPopover,
            listFocusedTab: _listFocusedTab,
            isWindowFocused: isWindowFocused,
            windowTitle: windowTitle
        )
        .environmentObject(containerService)
    }
}
