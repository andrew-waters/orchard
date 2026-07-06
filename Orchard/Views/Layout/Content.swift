import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    @EnvironmentObject var dnsService: DNSService
    @EnvironmentObject var networkService: NetworkService
    @EnvironmentObject var builderService: BuilderService
    @EnvironmentObject var statsService: StatsService
    @State private var selectedTab: TabSelection = .containers
    @State private var selectedContainer: String?
    @State private var selectedContainers: Set<String> = []
    @State private var selectedImage: String?
    @State private var selectedImages: Set<String> = []
    @State private var selectedMount: String?
    @State private var selectedMounts: Set<String> = []
    @State private var selectedDNSDomain: String?
    @State private var selectedDNSDomains: Set<String> = []
    @State private var pendingDNSSelection: String?
    @State private var selectedNetwork: String?
    @State private var selectedNetworks: Set<String> = []
    @State private var pendingNetworkSelection: String?

    // Last selected items to restore state
    @State private var lastSelectedContainer: String?
    @State private var lastSelectedImage: String?
    @State private var lastSelectedMount: String?
    @State private var lastSelectedDNSDomain: String?
    @State private var lastSelectedNetwork: String?

    // Last selected tabs for each section
    @State private var lastSelectedImageTab: String = "overview"
    @State private var lastSelectedMountTab: String = "overview"

    @State private var searchText: String = ""
    @State private var showOnlyRunning: Bool = false
    @State private var showOnlyImagesInUse: Bool = false
    @State private var showOnlyMountsInUse: Bool = false
    @State private var showImageSearch: Bool = false
    @State private var showAddDNSDomainSheet: Bool = false
    @State private var showAddNetworkSheet: Bool = false

    @State private var refreshTimer: Timer?

    @FocusState private var listFocusedTab: TabSelection?

    @State private var showingItemNavigatorPopover = false

    @Environment(\.openWindow) private var openWindow



    @ViewBuilder
    private var baseView: some View {
        Group {
            if systemService.systemStatus == .stopped {
                NotRunningView()
            } else if systemService.systemStatus == .newerVersion {
                NewerVersionView()
            } else if systemService.systemStatus == .unsupportedVersion {
                VersionIncompatibilityView()
            } else {
                MainInterfaceView(
                    selectedTab: $selectedTab,
                    selectedContainer: $selectedContainer,
                    selectedContainers: $selectedContainers,
                    selectedImage: $selectedImage,
                    selectedImages: $selectedImages,
                    selectedMount: $selectedMount,
                    selectedMounts: $selectedMounts,
                    selectedDNSDomain: $selectedDNSDomain,
                    selectedDNSDomains: $selectedDNSDomains,
                    selectedNetwork: $selectedNetwork,
                    selectedNetworks: $selectedNetworks,
                    lastSelectedContainer: $lastSelectedContainer,
                    lastSelectedImage: $lastSelectedImage,
                    lastSelectedMount: $lastSelectedMount,
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
                    showingItemNavigatorPopover: $showingItemNavigatorPopover,
                    listFocusedTab: _listFocusedTab,
                    windowTitle: "Orchard"
                )
                .navigationTitle("")
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .onDisappear {
                    stopRefreshTimer()
                }
            }
        }
    }

    private func applyServiceSyncHandlers(to view: some View) -> some View {
        view
            .onChange(of: containerListService.containers) { oldContainers, newContainers in
                if selectedContainer == nil && !newContainers.isEmpty && selectedTab == .containers {
                    selectedContainer = newContainers[0].configuration.id
                    selectedContainers = [newContainers[0].configuration.id]
                }
                let existingIds = Set(newContainers.map { $0.configuration.id })
                let pruned = selectedContainers.intersection(existingIds)
                if pruned != selectedContainers {
                    selectedContainers = pruned
                }
            }
            .onChange(of: imageService.images) { oldImages, newImages in
                if selectedImage == nil && !newImages.isEmpty && selectedTab == .images {
                    selectedImage = newImages[0].reference
                    selectedImages = [newImages[0].reference]
                }
                let existingIds = Set(newImages.map { $0.reference })
                let pruned = selectedImages.intersection(existingIds)
                if pruned != selectedImages {
                    selectedImages = pruned
                }
            }
            .onChange(of: containerListService.allMounts) { oldMounts, newMounts in
                if selectedMount == nil && !newMounts.isEmpty && selectedTab == .mounts {
                    selectedMount = newMounts[0].id
                    selectedMounts = [newMounts[0].id]
                }
                let existingIds = Set(newMounts.map { $0.id })
                let pruned = selectedMounts.intersection(existingIds)
                if pruned != selectedMounts {
                    selectedMounts = pruned
                }
            }
            .onChange(of: dnsService.dnsDomains) { oldDomains, newDomains in
                if let pending = pendingDNSSelection, newDomains.contains(where: { $0.domain == pending }) {
                    selectedDNSDomain = pending
                    selectedDNSDomains = [pending]
                    lastSelectedDNSDomain = pending
                    listFocusedTab = .dns
                    pendingDNSSelection = nil
                } else if selectedDNSDomain == nil && pendingDNSSelection == nil && !newDomains.isEmpty && selectedTab == .dns {
                    selectedDNSDomain = newDomains[0].domain
                    selectedDNSDomains = [newDomains[0].domain]
                }
                let existingIds = Set(newDomains.map { $0.domain })
                let pruned = selectedDNSDomains.intersection(existingIds)
                if pruned != selectedDNSDomains {
                    selectedDNSDomains = pruned
                }
            }
            .onChange(of: networkService.networks) { oldNetworks, newNetworks in
                if let pending = pendingNetworkSelection, newNetworks.contains(where: { $0.id == pending }) {
                    selectedNetwork = pending
                    selectedNetworks = [pending]
                    lastSelectedNetwork = pending
                    listFocusedTab = .networks
                    pendingNetworkSelection = nil
                } else if selectedNetwork == nil && pendingNetworkSelection == nil && !newNetworks.isEmpty && selectedTab == .networks {
                    selectedNetwork = newNetworks[0].id
                    selectedNetworks = [newNetworks[0].id]
                }
                let existingIds = Set(newNetworks.map { $0.id })
                let pruned = selectedNetworks.intersection(existingIds)
                if pruned != selectedNetworks {
                    selectedNetworks = pruned
                }
            }
    }

    private func applySelectionSyncHandlers(to view: some View) -> some View {
        view
            .onChange(of: selectedContainers) { _, newSet in
                if newSet.isEmpty {
                    if selectedContainer != nil { selectedContainer = nil }
                } else if let current = selectedContainer, newSet.contains(current) {
                } else {
                    selectedContainer = newSet.first
                }
            }
            .onChange(of: selectedContainer) { _, newValue in
                if let id = newValue {
                    if !selectedContainers.contains(id) {
                        selectedContainers = [id]
                    }
                } else {
                    if !selectedContainers.isEmpty {
                        selectedContainers = []
                    }
                }
            }
            .onChange(of: selectedImages) { _, newSet in
                if newSet.isEmpty {
                    if selectedImage != nil { selectedImage = nil }
                } else if let current = selectedImage, newSet.contains(current) {
                } else {
                    selectedImage = newSet.first
                }
            }
            .onChange(of: selectedImage) { _, newValue in
                if let id = newValue {
                    if !selectedImages.contains(id) {
                        selectedImages = [id]
                    }
                } else {
                    if !selectedImages.isEmpty {
                        selectedImages = []
                    }
                }
            }
            .onChange(of: selectedMounts) { _, newSet in
                if newSet.isEmpty {
                    if selectedMount != nil { selectedMount = nil }
                } else if let current = selectedMount, newSet.contains(current) {
                } else {
                    selectedMount = newSet.first
                }
            }
            .onChange(of: selectedMount) { _, newValue in
                if let id = newValue {
                    if !selectedMounts.contains(id) {
                        selectedMounts = [id]
                    }
                } else {
                    if !selectedMounts.isEmpty {
                        selectedMounts = []
                    }
                }
            }
            .onChange(of: selectedDNSDomains) { _, newSet in
                if newSet.isEmpty {
                    if selectedDNSDomain != nil { selectedDNSDomain = nil }
                } else if let current = selectedDNSDomain, newSet.contains(current) {
                } else {
                    selectedDNSDomain = newSet.first
                }
            }
            .onChange(of: selectedDNSDomain) { _, newValue in
                if let id = newValue {
                    if !selectedDNSDomains.contains(id) {
                        selectedDNSDomains = [id]
                    }
                } else {
                    if !selectedDNSDomains.isEmpty {
                        selectedDNSDomains = []
                    }
                }
            }
            .onChange(of: selectedNetworks) { _, newSet in
                if newSet.isEmpty {
                    if selectedNetwork != nil { selectedNetwork = nil }
                } else if let current = selectedNetwork, newSet.contains(current) {
                } else {
                    selectedNetwork = newSet.first
                }
            }
            .onChange(of: selectedNetwork) { _, newValue in
                if let id = newValue {
                    if !selectedNetworks.contains(id) {
                        selectedNetworks = [id]
                    }
                } else {
                    if !selectedNetworks.isEmpty {
                        selectedNetworks = []
                    }
                }
            }
    }

    private func applyNotificationHandlers(to view: some View) -> some View {
        view
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToContainer"))
            ) { notification in
                if let containerId = notification.object as? String {
                    selectedTab = TabSelection.containers
                    selectedContainer = containerId
                    selectedContainers = [containerId]
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToImage"))
            ) { notification in
                if let imageReference = notification.object as? String {
                    selectedTab = TabSelection.images
                    selectedImage = imageReference
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMount"))
            ) { notification in
                if let mountId = notification.object as? String {
                    selectedTab = TabSelection.mounts
                    selectedMount = mountId
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDNSDomain"))
            ) { notification in
                if let domainName = notification.object as? String {
                    pendingDNSSelection = domainName
                    selectedTab = TabSelection.dns
                    if dnsService.dnsDomains.contains(where: { $0.domain == domainName }) {
                        selectedDNSDomain = domainName
                        selectedDNSDomains = [domainName]
                        lastSelectedDNSDomain = domainName
                        listFocusedTab = .dns
                        pendingDNSSelection = nil
                    }
                    Task {
                        await dnsService.load(showLoading: false)
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToNetwork"))
            ) { notification in
                if let networkId = notification.object as? String {
                    pendingNetworkSelection = networkId
                    selectedTab = TabSelection.networks
                    if networkService.networks.contains(where: { $0.id == networkId }) {
                        selectedNetwork = networkId
                        selectedNetworks = [networkId]
                        lastSelectedNetwork = networkId
                        listFocusedTab = .networks
                        pendingNetworkSelection = nil
                    }
                    Task {
                        await networkService.load(showLoading: false)
                    }
                }
            }
    }

    var body: some View {
        applyNotificationHandlers(
            to: applySelectionSyncHandlers(
                to: applyServiceSyncHandlers(to: baseView)
            )
        )
        .onAppear {
            // Default tab is already set to containers
        }
        .task {
            await performInitialLoad()
            startRefreshTimer()
        }
    }


    private func performInitialLoad() async {
        await systemService.checkSystemStatus()

        // Load stats first for immediate display
        await statsService.load(showLoading: true)
        await systemService.loadSystemDiskUsage(showLoading: true)

        await containerListService.loadContainers(showLoading: true)
        await imageService.load()
        await builderService.loadBuilders()

        await dnsService.load(showLoading: true)
        await networkService.load(showLoading: true)
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                await systemService.checkSystemStatus()
                await containerListService.loadContainers(showLoading: false)
                await imageService.load()
                await builderService.loadBuilders()
                await dnsService.load(showLoading: false)
                await networkService.load(showLoading: false)
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

}
