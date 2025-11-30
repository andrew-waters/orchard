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
    @Binding var showImageSearch: Bool
    @Binding var showAddDNSDomainSheet: Bool
    @Binding var showAddNetworkSheet: Bool
    @Binding var isInIntentionalSettingsMode: Bool
    @Binding var showingItemNavigatorPopover: Bool
    @FocusState var listFocusedTab: TabSelection?
    let isWindowFocused: Bool
    let windowTitle: String

    // Computed properties
    private var currentResourceTitle: String {
        // Check if we're in intentional settings mode first
        if isInIntentionalSettingsMode {
            return "Settings"
        }

        // Check if we're in settings mode (no selections)
        let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil && selectedNetwork == nil

        if isSettingsMode && (selectedTab == .containers || selectedTab == .images || selectedTab == .mounts) {
            return "Settings"
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
        NavigationSplitView {
            SidebarView(
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
                searchText: $searchText,
                showOnlyRunning: $showOnlyRunning,
                showOnlyImagesInUse: $showOnlyImagesInUse,
                showImageSearch: $showImageSearch,
                showAddDNSDomainSheet: $showAddDNSDomainSheet,
                showAddNetworkSheet: $showAddNetworkSheet,
                isInIntentionalSettingsMode: $isInIntentionalSettingsMode,
                listFocusedTab: _listFocusedTab,
                isWindowFocused: isWindowFocused
            )
            .navigationSplitViewColumnWidth(
                min: 400, ideal: 500, max: 600)
            .opacity(isWindowFocused ? 1.0 : 0.75)
        } detail: {
            VStack(spacing: 0) {
                // Custom header
                if !currentResourceTitle.isEmpty {
                    CustomHeaderView(
                        title: currentResourceTitle,
                        subtitle: isInIntentionalSettingsMode ? nil : selectedTab.title,
                        showItemNavigator: true,
                        onItemNavigatorTap: {
                            showingItemNavigatorPopover = true
                        },
                        showingPopover: $showingItemNavigatorPopover,
                        popoverContent: {
                            ItemNavigatorPopover(
                                selectedTab: selectedTab,
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
                                showingItemNavigatorPopover: $showingItemNavigatorPopover,
                                showOnlyRunning: showOnlyRunning,
                                showOnlyImagesInUse: showOnlyImagesInUse,
                                searchText: searchText
                            )
                        }
                    ) {
                        AnyView(
                            HStack(spacing: 8) {
                                if let container = currentContainer {
                                    ContainerControlButton(
                                        container: container,
                                        isLoading: containerService.loadingContainers.contains(
                                            container.configuration.id),
                                        onStart: {
                                            Task { @MainActor in
                                                await containerService.startContainer(container.configuration.id)
                                            }
                                        },
                                        onStop: {
                                            Task { @MainActor in
                                                await containerService.stopContainer(container.configuration.id)
                                            }
                                        }
                                    )

                                    if container.status.lowercased() == "running" {
                                        ContainerTerminalButton(
                                            container: container,
                                            onOpenTerminal: {
                                                containerService.openTerminal(for: container.configuration.id)
                                            },
                                            onOpenTerminalBash: {
                                                containerService.openTerminalWithBash(for: container.configuration.id)
                                            }
                                        )
                                    } else {
                                        ContainerRemoveButton(
                                            container: container,
                                            isLoading: containerService.loadingContainers.contains(
                                                container.configuration.id),
                                            onRemove: {
                                                Task { @MainActor in
                                                    await containerService.removeContainer(container.configuration.id)
                                                }
                                            }
                                        )
                                    }

                                } else if let mount = currentMount {
                                    Button(action: {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: mount.mount.source))
                                    }) {
                                        SwiftUI.Image(systemName: "folder")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open in Finder")
                                }
                            }
                        )
                    }
                }

                // Main content
                DetailContentView(
                    selectedTab: selectedTab,
                    selectedContainer: selectedContainer,
                    selectedImage: selectedImage,
                    selectedMount: selectedMount,
                    selectedDNSDomain: selectedDNSDomain,
                    selectedNetwork: selectedNetwork,
                    isInIntentionalSettingsMode: isInIntentionalSettingsMode,
                    lastSelectedContainerTab: $lastSelectedContainerTab,
                    lastSelectedImageTab: $lastSelectedImageTab,
                    lastSelectedMountTab: $lastSelectedMountTab,
                    selectedTabBinding: $selectedTab,
                    selectedContainerBinding: $selectedContainer,
                    selectedNetworkBinding: $selectedNetwork
                )
            }
        }
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    // Always force settings mode without changing the tab
                    selectedContainer = nil
                    selectedImage = nil
                    selectedMount = nil
                    selectedDNSDomain = nil
                    isInIntentionalSettingsMode = true
                } label: {
                    SwiftUI.Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
    }
}
