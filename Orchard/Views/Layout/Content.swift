import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var isWindowFocused: Bool = true
    @State private var selectedTab: TabSelection = .containers
    @State private var selectedContainer: String?
    @State private var selectedImage: String?
    @State private var selectedMount: String?
    @State private var selectedDNSDomain: String?

    // Last selected items to restore state
    @State private var lastSelectedContainer: String?
    @State private var lastSelectedImage: String?
    @State private var lastSelectedMount: String?
    @State private var lastSelectedDNSDomain: String?

    // Last selected tabs for each section
    @State private var lastSelectedContainerTab: String = "overview"
    @State private var lastSelectedImageTab: String = "overview"
    @State private var lastSelectedMountTab: String = "overview"

    @State private var searchText: String = ""
    @State private var showOnlyRunning: Bool = false
    @State private var showOnlyImagesInUse: Bool = false
    @State private var showImageSearch: Bool = false
    @State private var showAddDNSDomainSheet: Bool = false

    @State private var refreshTimer: Timer?

    @FocusState private var listFocusedTab: TabSelection?

    @State private var showingItemNavigatorPopover = false
    @State private var isInIntentionalSettingsMode = false
    @State private var isInitialLoadComplete = false
    @Environment(\.openWindow) private var openWindow

    // Computed property for window title
    private var windowTitle: String {
        if let version = containerService.parsedContainerVersion {
            return "Container \(version)"
        }
        return "Container"
    }

    @ViewBuilder
    var body: some View {
        Group {
            if !isInitialLoadComplete {
                SplashScreenView(isInitialLoadComplete: $isInitialLoadComplete)
                    .task {
                        startRefreshTimer()
                    }
            } else if containerService.systemStatus == .stopped {
                NotRunningView()
            } else if containerService.systemStatus == .unsupportedVersion {
                VersionIncompatibilityView()
            } else {
                MainInterfaceView(
                    selectedTab: $selectedTab,
                    selectedContainer: $selectedContainer,
                    selectedImage: $selectedImage,
                    selectedMount: $selectedMount,
                    selectedDNSDomain: $selectedDNSDomain,
                    lastSelectedContainer: $lastSelectedContainer,
                    lastSelectedImage: $lastSelectedImage,
                    lastSelectedMount: $lastSelectedMount,
                    lastSelectedDNSDomain: $lastSelectedDNSDomain,
                    lastSelectedContainerTab: $lastSelectedContainerTab,
                    lastSelectedImageTab: $lastSelectedImageTab,
                    lastSelectedMountTab: $lastSelectedMountTab,
                    searchText: $searchText,
                    showOnlyRunning: $showOnlyRunning,
                    showOnlyImagesInUse: $showOnlyImagesInUse,
                    showImageSearch: $showImageSearch,
                    showAddDNSDomainSheet: $showAddDNSDomainSheet,
                    isInIntentionalSettingsMode: $isInIntentionalSettingsMode,
                    showingItemNavigatorPopover: $showingItemNavigatorPopover,
                    listFocusedTab: _listFocusedTab,
                    isWindowFocused: isWindowFocused,
                    windowTitle: windowTitle
                )
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                    isWindowFocused = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                    isWindowFocused = false
                }
                .onDisappear {
                    stopRefreshTimer()
                }
                .onChange(of: containerService.refreshInterval) { oldInterval, newInterval in
                    restartRefreshTimer()
                }
            }
        }
        .onAppear {
            // Default tab is already set to containers
        }
        .onChange(of: containerService.containers) { oldContainers, newContainers in
            // Auto-select first container when containers load, but not if we're intentionally in settings mode
            if selectedContainer == nil && !newContainers.isEmpty && !isInIntentionalSettingsMode {
                selectedContainer = newContainers[0].configuration.id
            }
            if selectedMount == nil && !containerService.allMounts.isEmpty && !isInIntentionalSettingsMode {
                selectedMount = containerService.allMounts[0].id
            }
        }
        .onChange(of: containerService.dnsDomains) { oldDomains, newDomains in
            // Auto-select first DNS domain when domains load, but not if we're intentionally in settings mode
            if selectedDNSDomain == nil && !newDomains.isEmpty && !isInIntentionalSettingsMode {
                selectedDNSDomain = newDomains[0].domain
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToContainer"))
        ) { notification in
            if let containerId = notification.object as? String {
                // Switch to containers view and select the specific container
                selectedTab = TabSelection.containers
                selectedContainer = containerId
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToImage"))
        ) { notification in
            if let imageReference = notification.object as? String {
                // Switch to images view and select the specific image
                selectedTab = TabSelection.images
                selectedImage = imageReference
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMount"))
        ) { notification in
            if let mountId = notification.object as? String {
                // Switch to mounts view and select the specific mount
                selectedTab = TabSelection.mounts
                selectedMount = mountId
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDNSDomain"))
        ) { notification in
            if let domainName = notification.object as? String {
                // Switch to DNS view and select the specific domain
                selectedTab = TabSelection.dns

                // Ensure DNS domains are loaded before selecting
                Task {
                    await containerService.loadDNSDomains()
                    await MainActor.run {
                        // Verify the domain exists in the loaded list
                        if containerService.dnsDomains.contains(where: { $0.domain == domainName }) {
                            // Add delay to ensure list is rendered before selection
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                selectedDNSDomain = domainName
                                lastSelectedDNSDomain = domainName
                                listFocusedTab = .dns
                            }
                        }
                    }
                }
            }
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: containerService.refreshInterval.timeInterval, repeats: true) { _ in
            Task { @MainActor in
                await containerService.checkSystemStatus()
                await containerService.loadContainers(showLoading: false)
                await containerService.loadImages()
                await containerService.loadBuilders()

                await containerService.loadDNSDomains(showLoading: false)

                // Check for updates periodically
                if containerService.shouldCheckForUpdates() {
                    await containerService.checkForUpdates()
                }
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func restartRefreshTimer() {
        stopRefreshTimer()
        startRefreshTimer()
    }
}
