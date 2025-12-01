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
    @Binding var showOnlyMountsInUse: Bool
    @Binding var showImageSearch: Bool
    @Binding var showAddDNSDomainSheet: Bool
    @Binding var showAddNetworkSheet: Bool
    @Binding var isInIntentionalSettingsMode: Bool
    @Binding var showingItemNavigatorPopover: Bool
    @FocusState var listFocusedTab: TabSelection?
    let isWindowFocused: Bool
    let windowTitle: String

    private var needsMiddleColumn: Bool {
        switch selectedTab {
        case .containers, .images, .mounts, .dns, .networks:
            return true
        case .registries, .systemLogs, .settings:
            return false
        }
    }

    var body: some View {
        if needsMiddleColumn {
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
                    listFocusedTab: $listFocusedTab,
                    isWindowFocused: isWindowFocused
                )
                .environmentObject(containerService)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } content: {
                // Second Column - List view for selected tab
                VStack(spacing: 0) {
                    // Translucent header like Mail with search
                    VStack(spacing: 8) {
                        // Search and filters
                        if selectedTab != .registries && selectedTab != .systemLogs && selectedTab != .settings {
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
                                        SwiftUI.Image(systemName: showOnlyRunning ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                            .foregroundColor(showOnlyRunning ? .accentColor : .secondary)
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Show only running containers")
                                } else if selectedTab == .images {
                                    Button(action: { showOnlyImagesInUse.toggle() }) {
                                        SwiftUI.Image(systemName: showOnlyImagesInUse ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                            .foregroundColor(showOnlyImagesInUse ? .accentColor : .secondary)
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Show only images in use")
                                } else if selectedTab == .mounts {
                                    Button(action: { showOnlyMountsInUse.toggle() }) {
                                        SwiftUI.Image(systemName: showOnlyMountsInUse ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                            .foregroundColor(showOnlyMountsInUse ? .accentColor : .secondary)
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Show only mounts in use")
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
                        showOnlyMountsInUse: $showOnlyMountsInUse,
                        showImageSearch: $showImageSearch,
                        showAddDNSDomainSheet: $showAddDNSDomainSheet,
                        showAddNetworkSheet: $showAddNetworkSheet,
                        listFocusedTab: _listFocusedTab
                    )
                }
                .environmentObject(containerService)
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
            } detail: {
                // Third Column - Detail view for selected item
                DetailContentView(
                    selectedTab: selectedTab,
                    selectedContainer: selectedContainer,
                    selectedImage: selectedImage,
                    selectedMount: selectedMount,
                    selectedDNSDomain: selectedDNSDomain,
                    selectedNetwork: selectedNetwork,
                    isInIntentionalSettingsMode: isInIntentionalSettingsMode,
                    lastSelectedContainerTab: $lastSelectedContainerTab,
                    selectedTabBinding: $selectedTab,
                    selectedContainerBinding: $selectedContainer,
                    selectedNetworkBinding: $selectedNetwork
                )
            }
        } else {
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
                    listFocusedTab: $listFocusedTab,
                    isWindowFocused: isWindowFocused
                )
                .environmentObject(containerService)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } detail: {
                // Two-column layout - Detail view only
                DetailContentView(
                    selectedTab: selectedTab,
                    selectedContainer: selectedContainer,
                    selectedImage: selectedImage,
                    selectedMount: selectedMount,
                    selectedDNSDomain: selectedDNSDomain,
                    selectedNetwork: selectedNetwork,
                    isInIntentionalSettingsMode: isInIntentionalSettingsMode,
                    lastSelectedContainerTab: $lastSelectedContainerTab,
                    selectedTabBinding: $selectedTab,
                    selectedContainerBinding: $selectedContainer,
                    selectedNetworkBinding: $selectedNetwork
                )
            }
        }

    }

    // Computed properties for detail column

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
    @FocusState.Binding var listFocusedTab: TabSelection?
    let isWindowFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            sidebarList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .opacity(isWindowFocused ? 1.0 : 0.5)
        .onAppear {
            // Set initial focus when view appears
            switch selectedTab {
            case .containers, .images, .mounts, .dns, .networks:
                DispatchQueue.main.async {
                    listFocusedTab = selectedTab
                }
            case .registries, .systemLogs, .settings:
                break
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            selectTab(newTab)
        }
    }

   private var sidebarList: some View {
        List {
            ForEach(TabSelection.allCases, id: \.self) { tab in
                sidebarRow(for: tab)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sidebarRow(for tab: TabSelection) -> some View {
        HStack(spacing: 6) {
            SwiftUI.Image(systemName: tab.icon)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 20)
                .foregroundColor(selectedTab == tab ? .accentColor : .primary)

            Text(tab.title)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(selectedTab == tab ? .accentColor : .primary)

            Spacer()

            if getTabCount(for: tab) > 0 {
                Text("\(getTabCount(for: tab))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(selectedTab == tab ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            selectedTab == tab ? Color.secondary.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectTab(tab)
        }
    }



    private func selectTab(_ tab: TabSelection) {
        selectedTab = tab

        if tab == .settings {
            selectedContainer = nil
            selectedImage = nil
            selectedMount = nil
            selectedDNSDomain = nil
            isInIntentionalSettingsMode = true
        } else if isInIntentionalSettingsMode {
            isInIntentionalSettingsMode = false
        }

        // Auto-select first item in tabs with second columns (only if no selection exists)
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
        case .registries, .systemLogs, .settings:
            // Clear all selections for tabs without second columns
            selectedContainer = nil
            selectedImage = nil
            selectedMount = nil
            selectedDNSDomain = nil
            selectedNetwork = nil
            break
        }

        // Set focus after state changes
        listFocusedTab = nil
        DispatchQueue.main.async {
            switch tab {
            case .containers, .images, .mounts, .dns, .networks:
                self.listFocusedTab = tab
            case .registries, .systemLogs, .settings:
                self.listFocusedTab = nil
            }
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
        case .registries, .systemLogs, .settings:
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
    @Binding var showOnlyMountsInUse: Bool
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
                    showOnlyMountsInUse: $showOnlyMountsInUse,
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
            case .settings:
                EmptyStateView(
                    title: "Settings",
                    subtitle: "Settings configuration"
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
