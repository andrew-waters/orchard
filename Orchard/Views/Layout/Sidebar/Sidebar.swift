import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    @EnvironmentObject var dnsService: DNSService
    @EnvironmentObject var networkService: NetworkService
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
    @Binding var searchText: String
    @Binding var showOnlyRunning: Bool
    @Binding var showOnlyImagesInUse: Bool
    @Binding var showOnlyMountsInUse: Bool
    @Binding var showImageSearch: Bool
    @Binding var showAddDNSDomainSheet: Bool
    @Binding var showAddNetworkSheet: Bool
    @Binding var isInIntentionalConfigurationMode: Bool
    @FocusState var listFocusedTab: TabSelection?
    let isWindowFocused: Bool
    @State private var selectedContainersLocal: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            SidebarTabs(
                selectedTab: $selectedTab,
                selectedContainer: $selectedContainer,
                selectedImage: $selectedImage,
                selectedMount: $selectedMount,
                selectedDNSDomain: $selectedDNSDomain,
                selectedNetwork: $selectedNetwork,
                isInIntentionalConfigurationMode: $isInIntentionalConfigurationMode,
                listFocusedTab: $listFocusedTab,
                isWindowFocused: isWindowFocused
            )
            Divider()
            selectedContentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedTab) { _, newTab in
            // Restore previous selection or select first element when changing tabs
            // But only if there's no current selection (to avoid overriding navigation selections)
            switch newTab {
            case .containers:
                if selectedContainer == nil {
                    if let lastSelected = lastSelectedContainer,
                       filteredContainers.contains(where: { $0.configuration.id == lastSelected }) {
                        selectedContainer = lastSelected
                    } else if !filteredContainers.isEmpty {
                        selectedContainer = filteredContainers.first?.configuration.id
                    }
                }
            case .images:
                if selectedImage == nil {
                    if let lastSelected = lastSelectedImage,
                       filteredImages.contains(where: { $0.reference == lastSelected }) {
                        selectedImage = lastSelected
                    } else if !filteredImages.isEmpty {
                        selectedImage = filteredImages.first?.reference
                    }
                }
            case .mounts:
                if selectedMount == nil {
                    if let lastSelected = lastSelectedMount,
                       filteredMounts.contains(where: { $0.id == lastSelected }) {
                        selectedMount = lastSelected
                    } else if !filteredMounts.isEmpty {
                        selectedMount = filteredMounts.first?.id
                    }
                }
            case .dns:
                if selectedDNSDomain == nil {
                    if let lastSelected = lastSelectedDNSDomain,
                       dnsService.dnsDomains.contains(where: { $0.domain == lastSelected }) {
                        selectedDNSDomain = lastSelected
                    } else if !dnsService.dnsDomains.isEmpty {
                        selectedDNSDomain = dnsService.dnsDomains.first?.domain
                    }
                }
            case .networks:
                if selectedNetwork == nil {
                    if let lastSelected = lastSelectedNetwork,
                       networkService.networks.contains(where: { $0.id == lastSelected }) {
                        selectedNetwork = lastSelected
                    } else if !networkService.networks.isEmpty {
                        selectedNetwork = networkService.networks.first?.id
                    }
                }
            case .registries, .systemLogs, .dashboard, .configuration:
                // No selection state for these tabs
                break
            }

            // Set focus to the current tab's list
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                listFocusedTab = newTab
            }
        }
    }

    private var selectedContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Check if we're in configuration mode (no selections)
            let isConfigurationMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil && selectedNetwork == nil

            if isConfigurationMode && isInIntentionalConfigurationMode {
                // Show empty state when intentionally in configuration mode
                VStack {
                    Text("Configuration")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Configure app preferences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .containers:
                    ContainersListView(
                        selectedContainer: $selectedContainer,
                        selectedContainers: $selectedContainersLocal,
                        lastSelectedContainer: $lastSelectedContainer,
                        searchText: $searchText,
                        showOnlyRunning: $showOnlyRunning,
                        listFocusedTab: _listFocusedTab
                    )
                case .images:
                    ImagesListView(
                        selectedImage: $selectedImage,
                        lastSelectedImage: $lastSelectedImage,
                        searchText: $searchText,
                        showOnlyImagesInUse: $showOnlyImagesInUse,
                        showImageSearch: $showImageSearch,
                        listFocusedTab: _listFocusedTab
                    )
                case .mounts:
                    MountsListView(
                        selectedMount: $selectedMount,
                        lastSelectedMount: $lastSelectedMount,
                        searchText: $searchText,
                        showOnlyMountsInUse: $showOnlyMountsInUse,
                        listFocusedTab: _listFocusedTab
                    )
                case .dns:
                    DNSListView(
                        selectedDNSDomain: $selectedDNSDomain,
                        lastSelectedDNSDomain: $lastSelectedDNSDomain,
                        showAddDNSDomainSheet: $showAddDNSDomainSheet,
                        listFocusedTab: _listFocusedTab
                    )
                case .networks:
                    NetworksListView(
                        selectedNetwork: $selectedNetwork,
                        lastSelectedNetwork: $lastSelectedNetwork,
                        showAddNetworkSheet: $showAddNetworkSheet,
                        listFocusedTab: _listFocusedTab
                    )
                case .registries:
                    registriesView
                case .systemLogs:
                    systemLogsView
                case .dashboard:
                    statsView
                case .configuration:
                    VStack {
                        Text("Configuration")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Configure app preferences")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Set initial focus when view appears
            switch selectedTab {
            case .containers, .images, .mounts, .dns, .networks:
                DispatchQueue.main.async {
                    listFocusedTab = selectedTab
                }
            case .registries, .systemLogs, .dashboard, .configuration:
                break
            }
        }
    }

    private var registriesView: some View {
        VStack {
            Text("No registries to display")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var systemLogsView: some View {
        VStack {
            Text("System Logs")
                .font(.title)
                .foregroundColor(.secondary)
            Text("Coming Soon")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statsView: some View {
        VStack {
            Text("Container Stats")
                .font(.title2)
                .fontWeight(.medium)
            Text("Real-time container statistics")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Helper computed properties for filtering
    private var filteredContainers: [Container] {
        var filtered = containerListService.containers

        if showOnlyRunning {
            filtered = filtered.filter { $0.status.lowercased() == "running" }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { container in
                container.configuration.id.localizedCaseInsensitiveContains(searchText)
                    || container.status.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    private var filteredImages: [ContainerImage] {
        var filtered = imageService.images

        if showOnlyImagesInUse {
            filtered = filtered.filter { image in
                containerListService.containers.contains { container in
                    container.configuration.image.reference == image.reference
                }
            }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { image in
                image.reference.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    private var filteredMounts: [ContainerMount] {
        var filtered = containerListService.allMounts

        if showOnlyMountsInUse {
            filtered = filtered.filter { mount in
                // Only show mounts used by running containers
                mount.containerIds.contains { containerID in
                    containerListService.containers.first { $0.configuration.id == containerID }?.status.lowercased() == "running"
                }
            }
        }

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
