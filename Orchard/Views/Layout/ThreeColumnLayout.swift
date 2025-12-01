import SwiftUI
import AppKit

struct ThreeColumnLayout: View {
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

    var body: some View {
        NavigationSplitView {
            // First Column - Sidebar with navigation tabs
            TabColumnView(
                selectedTab: $selectedTab,
                selectedContainer: $selectedContainer,
                selectedImage: $selectedImage,
                selectedMount: $selectedMount,
                selectedDNSDomain: $selectedDNSDomain,
                selectedNetwork: $selectedNetwork,
                isInIntentionalSettingsMode: $isInIntentionalSettingsMode,
                isWindowFocused: isWindowFocused
            )
            .environmentObject(containerService)
        } content: {
            // Second Column - List view for selected tab
            VStack(spacing: 0) {
                // Translucent header like Mail with search
                VStack(spacing: 8) {
                    HStack {
                        Text(selectedTab.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    // Search and filters
                    if selectedTab != .registries && selectedTab != .systemLogs {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                SwiftUI.Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 11))

                                TextField("Search \(selectedTab.title.lowercased())", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            // Tab-specific filters
                            if selectedTab == .containers {
                                Button(action: { showOnlyRunning.toggle() }) {
                                    SwiftUI.Image(systemName: showOnlyRunning ? "play.circle.fill" : "play.circle")
                                        .foregroundColor(showOnlyRunning ? .green : .secondary)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .help("Show only running containers")
                            } else if selectedTab == .images {
                                Button(action: { showOnlyImagesInUse.toggle() }) {
                                    SwiftUI.Image(systemName: showOnlyImagesInUse ? "cube.fill" : "cube")
                                        .foregroundColor(showOnlyImagesInUse ? .blue : .secondary)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .help("Show only images in use")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Rectangle())

                ListColumnView(
                    selectedTab: selectedTab,
                    selectedContainer: $selectedContainer,
                    selectedImage: $selectedImage,
                    selectedMount: $selectedMount,
                    selectedDNSDomain: $selectedDNSDomain,
                    selectedNetwork: $selectedNetwork,
                    lastSelectedContainer: lastSelectedContainer,
                    lastSelectedImage: lastSelectedImage,
                    lastSelectedMount: lastSelectedMount,
                    lastSelectedDNSDomain: lastSelectedDNSDomain,
                    lastSelectedNetwork: lastSelectedNetwork,
                    searchText: $searchText,
                    showOnlyRunning: $showOnlyRunning,
                    showOnlyImagesInUse: $showOnlyImagesInUse,
                    showImageSearch: $showImageSearch,
                    showAddDNSDomainSheet: $showAddDNSDomainSheet,
                    showAddNetworkSheet: $showAddNetworkSheet,
                    listFocusedTab: _listFocusedTab
                )
            }
            .environmentObject(containerService)
        } detail: {
            // Third Column - Detail view for selected item
            VStack(spacing: 0) {
                // Translucent header like Mail
                if !currentResourceTitle.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentResourceTitle)
                                .font(.title2)
                                .fontWeight(.semibold)
                            if !isInIntentionalSettingsMode {
                                Text(selectedTab.title)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()

                        // Action buttons for containers
                        HStack(spacing: 8) {
                            if let container = currentContainer {
                                ContainerControlButton(
                                    container: container,
                                    isLoading: containerService.loadingContainers.contains(container.configuration.id),
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
                                        isLoading: containerService.loadingContainers.contains(container.configuration.id),
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Rectangle())
                }

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
            .environmentObject(containerService)
        }

    }

    // Computed properties for detail column
    private var currentResourceTitle: String {
        if isInIntentionalSettingsMode {
            return "Settings"
        }

        let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil && selectedNetwork == nil

        if isSettingsMode && (selectedTab == .containers || selectedTab == .images || selectedTab == .mounts) {
            return "Settings"
        }

        switch selectedTab {
        case .containers:
            return selectedContainer ?? ""
        case .images:
            if let selectedImage = selectedImage {
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
            return selectedDNSDomain ?? ""
        case .networks:
            return selectedNetwork ?? ""
        case .registries, .systemLogs:
            return ""
        }
    }

    private var currentContainer: Container? {
        guard selectedTab == .containers, let selectedContainer = selectedContainer else { return nil }
        return containerService.containers.first { $0.configuration.id == selectedContainer }
    }

    private var currentMount: ContainerMount? {
        guard selectedTab == .mounts, let selectedMount = selectedMount else { return nil }
        return containerService.allMounts.first { $0.id == selectedMount }
    }
}

// MARK: - Tab Column View (First Column)
struct TabColumnView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @Binding var selectedImage: String?
    @Binding var selectedMount: String?
    @Binding var selectedDNSDomain: String?
    @Binding var selectedNetwork: String?
    @Binding var isInIntentionalSettingsMode: Bool
    let isWindowFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Tab selection list
            List(selection: $selectedTab) {
                ForEach(TabSelection.allCases, id: \.self) { tab in
                    HStack(spacing: 8) {
                        SwiftUI.Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 16)
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)

                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        if getTabCount(for: tab) > 0 {
                            Text("\(getTabCount(for: tab))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectTab(tab)
                    }
                }
            }
            .listStyle(.sidebar)

            // Settings button
            Divider()
            Button(action: {
                selectedContainer = nil
                selectedImage = nil
                selectedMount = nil
                selectedDNSDomain = nil
                isInIntentionalSettingsMode = true
            }) {
                HStack(spacing: 8) {
                    SwiftUI.Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                    Text("Settings")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isWindowFocused ? 1.0 : 0.75)
        .onChange(of: selectedTab) { _, newTab in
            selectTab(newTab)
        }
    }

    private func selectTab(_ tab: TabSelection) {
        selectedTab = tab

        if isInIntentionalSettingsMode {
            isInIntentionalSettingsMode = false
        }

        // Auto-select first item in the new tab
        switch tab {
        case .containers:
            if selectedContainer == nil && !containerService.containers.isEmpty {
                selectedContainer = containerService.containers.first?.configuration.id
            }
        case .images:
            if selectedImage == nil && !containerService.images.isEmpty {
                selectedImage = containerService.images.first?.reference
            }
        case .mounts:
            if selectedMount == nil && !containerService.allMounts.isEmpty {
                selectedMount = containerService.allMounts.first?.id
            }
        case .dns:
            if selectedDNSDomain == nil && !containerService.dnsDomains.isEmpty {
                selectedDNSDomain = containerService.dnsDomains.first?.domain
            }
        case .networks:
            if selectedNetwork == nil && !containerService.networks.isEmpty {
                selectedNetwork = containerService.networks.first?.id
            }
        case .registries, .systemLogs:
            break
        }
    }

    private func getTabCount(for tab: TabSelection) -> Int {
        switch tab {
        case .containers:
            return containerService.containers.count
        case .images:
            return containerService.images.count
        case .mounts:
            return containerService.allMounts.count
        case .dns:
            return containerService.dnsDomains.count
        case .networks:
            return containerService.networks.count
        case .registries, .systemLogs:
            return 0
        }
    }
}

// MARK: - List Column View (Second Column)
struct ListColumnView: View {
    @EnvironmentObject var containerService: ContainerService
    let selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @Binding var selectedImage: String?
    @Binding var selectedMount: String?
    @Binding var selectedDNSDomain: String?
    @Binding var selectedNetwork: String?
    let lastSelectedContainer: String?
    let lastSelectedImage: String?
    let lastSelectedMount: String?
    let lastSelectedDNSDomain: String?
    let lastSelectedNetwork: String?
    @Binding var searchText: String
    @Binding var showOnlyRunning: Bool
    @Binding var showOnlyImagesInUse: Bool
    @Binding var showImageSearch: Bool
    @Binding var showAddDNSDomainSheet: Bool
    @Binding var showAddNetworkSheet: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {

            // List content
            switch selectedTab {
            case .containers:
                ContainersListView(
                    selectedContainer: $selectedContainer,
                    lastSelectedContainer: .constant(lastSelectedContainer),
                    searchText: $searchText,
                    showOnlyRunning: $showOnlyRunning,
                    listFocusedTab: _listFocusedTab
                )
            case .images:
                ImagesListView(
                    selectedImage: $selectedImage,
                    lastSelectedImage: .constant(lastSelectedImage),
                    searchText: $searchText,
                    showOnlyImagesInUse: $showOnlyImagesInUse,
                    showImageSearch: $showImageSearch,
                    listFocusedTab: _listFocusedTab
                )
            case .mounts:
                MountsListView(
                    selectedMount: $selectedMount,
                    lastSelectedMount: .constant(lastSelectedMount),
                    searchText: $searchText,
                    listFocusedTab: _listFocusedTab
                )
            case .dns:
                DNSListView(
                    selectedDNSDomain: $selectedDNSDomain,
                    lastSelectedDNSDomain: .constant(lastSelectedDNSDomain),
                    showAddDNSDomainSheet: $showAddDNSDomainSheet,
                    listFocusedTab: _listFocusedTab
                )
            case .networks:
                NetworksListView(
                    selectedNetwork: $selectedNetwork,
                    lastSelectedNetwork: .constant(lastSelectedNetwork),
                    showAddNetworkSheet: $showAddNetworkSheet,
                    listFocusedTab: _listFocusedTab
                )
            case .registries:
                EmptyStateView(
                    title: "No registries",
                    subtitle: "Registries will appear here"
                )
            case .systemLogs:
                EmptyStateView(
                    title: "System Logs",
                    subtitle: "System logs will appear here"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
}

// MARK: - Detail Column View (Third Column)
struct DetailColumnView: View {
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
    @Binding var selectedNetworkBinding: String?
    @Binding var showingItemNavigatorPopover: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Detail content without header (header is now in ThreeColumnLayout)
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
                selectedTabBinding: $selectedTabBinding,
                selectedContainerBinding: $selectedContainerBinding,
                selectedNetworkBinding: $selectedNetworkBinding
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2)
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
