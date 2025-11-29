//
//  ContentView.swift
//  Orchard
//
//  Created by Andrew Waters on 16/06/2025.
//

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
    @Environment(\.openWindow) private var openWindow

    // Computed property for window title
    private var windowTitle: String {
        if let version = containerService.parsedContainerVersion {
            return "Container \(version)"
        }
        return "Container"
    }

    // Computed property for current resource title
    private var currentResourceTitle: String {
        // Check if we're in intentional settings mode first
        if isInIntentionalSettingsMode {
            return "Settings"
        }

        // Check if we're in settings mode (no selections)
        let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil

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

    // Get current image for title bar display
    private var currentImage: ContainerImage? {
        guard selectedTab == .images, let selectedImage = selectedImage else { return nil }
        return containerService.images.first { $0.reference == selectedImage }
    }

    // Get current mount for title bar display
    private var currentMount: ContainerMount? {
        guard selectedTab == .mounts, let selectedMount = selectedMount else { return nil }
        return containerService.allMounts.first { $0.id == selectedMount }
    }

    enum TabSelection: String, CaseIterable {
        case containers = "containers"
        case images = "images"
        case mounts = "mounts"
        case dns = "dns"
        case registries = "registries"
        case systemLogs = "systemLogs"

        var icon: String {
            switch self {
            case .containers:
                return "cube"
            case .images:
                return "cube.transparent"
            case .mounts:
                return "externaldrive"
            case .dns:
                return "network"
            case .registries:
                return "server.rack"
            case .systemLogs:
                return "doc.text.below.ecg"
            }
        }

        var title: String {
            switch self {
            case .containers:
                return "Containers"
            case .images:
                return "Images"
            case .mounts:
                return "Mounts"
            case .dns:
                return "DNS"
            case .registries:
                return "Registries"
            case .systemLogs:
                return "System Logs"
            }
        }
    }

    var body: some View {
        Group {
            if containerService.systemStatus == .stopped {
                emptyStateView
            } else if containerService.systemStatus == .unsupportedVersion {
                versionIncompatibilityView
            } else {
                mainInterfaceView
            }
        }
        .onAppear {
            // Default tab is already set to containers
        }
        .onChange(of: containerService.containers) { _, newContainers in
            // Auto-select first container when containers load, but not if we're intentionally in settings mode
            if selectedContainer == nil && !newContainers.isEmpty && !isInIntentionalSettingsMode {
                selectedContainer = newContainers[0].configuration.id
            }
            if selectedMount == nil && !containerService.allMounts.isEmpty && !isInIntentionalSettingsMode {
                selectedMount = containerService.allMounts[0].id
            }
        }
        .onChange(of: containerService.dnsDomains) { _, newDomains in
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
                selectedTab = .containers
                selectedContainer = containerId
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToImage"))
        ) { notification in
            if let imageReference = notification.object as? String {
                // Switch to images view and select the specific image
                selectedTab = .images
                selectedImage = imageReference
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMount"))
        ) { notification in
            if let mountId = notification.object as? String {
                // Switch to mounts view and select the specific mount
                selectedTab = .mounts
                selectedMount = mountId
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDNSDomain"))
        ) { notification in
            if let domainName = notification.object as? String {
                // Switch to DNS view and select the specific domain
                selectedTab = .dns

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

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            PowerButton(
                isLoading: containerService.isSystemLoading,
                action: {
                    Task { @MainActor in
                        await containerService.startSystem()
                    }
                }
            )

            Text("Container is not currently runnning")
                .font(.title2)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            await containerService.checkSystemStatus()
            await containerService.loadContainers(showLoading: true)
            await containerService.loadImages()
            await containerService.loadBuilders()
        }
    }

    private var versionIncompatibilityView: some View {
        VStack(spacing: 30) {
            SwiftUI.Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 16) {
                Text("Unsupported Container Version")
                    .font(.title)
                    .fontWeight(.semibold)

                if let installedVersion = containerService.parsedContainerVersion {
                    Text("We require Apple Container version \(containerService.supportedContainerVersion), but you are running version \(installedVersion)")
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                } else if let rawVersion = containerService.containerVersion {
                    Text("Detected version: \(rawVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)

                    Text("We require Apple Container version \(containerService.supportedContainerVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("We require Apple Container version \(containerService.supportedContainerVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Please update your Container installation to continue using this application.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: 16) {
                Button("View upgrade instructions") {
                    if let url = URL(string: "https://github.com/apple/container?tab=readme-ov-file#install-or-upgrade") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Check Again") {
                    Task { @MainActor in
                        await containerService.checkSystemStatus()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            await containerService.checkSystemStatus()
        }
    }

    private var mainInterfaceView: some View {
        NavigationSplitView {
            primaryColumnView
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
                    .popover(isPresented: $showingItemNavigatorPopover) {
                        itemNavigatorPopoverView
                    }
                }

                // Main content
                detailView
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isWindowFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isWindowFocused = false
        }
        .task {
            await containerService.checkSystemStatus()
            await containerService.loadContainers(showLoading: true)
            await containerService.loadImages()
            await containerService.loadBuilders()

            await containerService.loadDNSDomains(showLoading: true)

            // Check for updates on startup
            if containerService.shouldCheckForUpdates() {
                await containerService.checkForUpdates()
            }

            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onChange(of: containerService.refreshInterval) { _, _ in
            restartRefreshTimer()
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

    private var primaryColumnView: some View {
        VStack(spacing: 0) {
            iconTabBar
            Divider()
            selectedContentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: selectedTab) { _, newTab in
            // Restore previous selection or select first element when changing tabs
            switch newTab {
            case .containers:
                if let lastSelected = lastSelectedContainer,
                   filteredContainers.contains(where: { $0.configuration.id == lastSelected }) {
                    selectedContainer = lastSelected
                } else if !filteredContainers.isEmpty {
                    selectedContainer = filteredContainers.first?.configuration.id
                }
            case .images:
                if let lastSelected = lastSelectedImage,
                   filteredImages.contains(where: { $0.reference == lastSelected }) {
                    selectedImage = lastSelected
                } else if !filteredImages.isEmpty {
                    selectedImage = filteredImages.first?.reference
                }
            case .mounts:
                if let lastSelected = lastSelectedMount,
                   filteredMounts.contains(where: { $0.id == lastSelected }) {
                    selectedMount = lastSelected
                } else if !filteredMounts.isEmpty {
                    selectedMount = filteredMounts.first?.id
                }
            case .dns:
                if let lastSelected = lastSelectedDNSDomain,
                   containerService.dnsDomains.contains(where: { $0.domain == lastSelected }) {
                    selectedDNSDomain = lastSelected
                } else if !containerService.dnsDomains.isEmpty {
                    selectedDNSDomain = containerService.dnsDomains.first?.domain
                }
            case .registries, .systemLogs:
                // No selection state for these tabs
                break
            }

            // Set focus to the current tab's list
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                listFocusedTab = newTab
            }
        }
    }







    private var itemNavigatorPopoverView: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverHeader
            Divider()
            popoverContent
        }
        .frame(width: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var iconTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(TabSelection.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab

                        // If we're in settings mode and clicking a tab, select a default item to exit settings mode
                        let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil
                        if isSettingsMode {
                            isInIntentionalSettingsMode = false
                            switch tab {
                            case .containers:
                                if let firstContainer = containerService.containers.first {
                                    selectedContainer = firstContainer.configuration.id
                                }
                            case .images:
                                if let firstImage = containerService.images.first {
                                    selectedImage = firstImage.reference
                                }
                            case .mounts:
                                if let firstMount = containerService.allMounts.first {
                                    selectedMount = firstMount.id
                                }
                            case .dns:
                                if let firstDomain = containerService.dnsDomains.first {
                                    selectedDNSDomain = firstDomain.domain
                                }
                            case .registries, .systemLogs:
                                break // These don't have selectable items
                            }
                        }
                    }) {
                        let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil
                        let isActiveTab = selectedTab == tab && !isSettingsMode && !isInIntentionalSettingsMode

                        SwiftUI.Image(systemName: tab.icon)
                            .font(.system(size: 14))
                            .foregroundColor(isActiveTab ? (isWindowFocused ? .accentColor : .secondary) : (isWindowFocused ? .secondary : Color.secondary.opacity(0.5)))
                            .frame(width: 32, height: 32)
                            .background(
                                isActiveTab ? Color.accentColor.opacity(isWindowFocused ? 0.15 : 0.08) : Color.clear
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var selectedContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
                // Check if we're in settings mode (no selections)
                let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil

                if isSettingsMode && (selectedTab == .containers || selectedTab == .images || selectedTab == .mounts) {
                    // Show empty state when in settings mode
                    VStack {
                        Text("Settings")
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
                        containersList
                    case .images:
                        imagesList
                    case .mounts:
                        mountsList
                    case .dns:
                        dnsView
                    case .registries:
                        registriesView
                    case .systemLogs:
                        systemLogsView
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }




    private var dnsView: some View {
        VStack(spacing: 0) {
            if containerService.isDNSLoading {
                VStack {
                    ProgressView()
                        .padding()
                    Text("Loading DNS domains...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if containerService.dnsDomains.isEmpty {
                VStack {
                    SwiftUI.Image(systemName: "network.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text("No DNS Domains")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add a domain to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // DNS domain list
                List(selection: $selectedDNSDomain) {
                    ForEach(containerService.dnsDomains) { domain in
                        HStack {
                            SwiftUI.Image(systemName: "network")
                                .foregroundColor(.gray)
                                .frame(width: 16, height: 16)

                            Text(domain.domain)
                        }
                        .tag(domain.domain)
                    }
                }
                .listStyle(PlainListStyle())
                .animation(.easeInOut(duration: 0.3), value: containerService.dnsDomains)
                .focused($listFocusedTab, equals: .dns)
                .onChange(of: selectedDNSDomain) { _, newValue in
                    lastSelectedDNSDomain = newValue
                }
            }

            // Add domain button
            HStack {
                Button(action: {
                    showAddDNSDomainSheet = true
                }) {
                    HStack {
                        SwiftUI.Image(systemName: "plus")
                            .font(.system(size: 12))
                        Text("Add Domain")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddDNSDomainSheet) {
            AddDNSDomainView()
                .environmentObject(containerService)
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
            Text("System logs will go here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }



    private var popoverHeader: some View {
        HStack {
            SwiftUI.Image(systemName: selectedTab.icon)
                .font(.headline)
            Text(selectedTab.title)
                .font(.headline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var popoverContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch selectedTab {
                case .containers:
                    containerPopoverItems
                case .images:
                    imagePopoverItems
                case .mounts:
                    mountPopoverItems
                case .dns:
                    dnsPopoverItems
                case .registries, .systemLogs:
                    EmptyView()
                }
            }
        }
        .frame(maxHeight: 300)
    }

    private var containerPopoverItems: some View {
        ForEach(filteredContainers, id: \.configuration.id) { container in
            containerPopoverRow(container)
            if container.configuration.id != filteredContainers.last?.configuration.id {
                Divider().padding(.leading)
            }
        }
    }

    private func containerPopoverRow(_ container: Container) -> some View {
        Button(action: {
            selectedContainer = container.configuration.id
            lastSelectedContainer = container.configuration.id
            showingItemNavigatorPopover = false
        }) {
            HStack {
                Circle()
                    .fill(container.status.lowercased() == "running" ? .green : .gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.configuration.id)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(container.status.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if selectedContainer == container.configuration.id {
                    SwiftUI.Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(selectedContainer == container.configuration.id ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var imagePopoverItems: some View {
        ForEach(filteredImages, id: \.reference) { image in
            imagePopoverRow(image)
            if image.reference != filteredImages.last?.reference {
                Divider().padding(.leading)
            }
        }
    }

    private func imagePopoverRow(_ image: ContainerImage) -> some View {
        Button(action: {
            selectedImage = image.reference
            lastSelectedImage = image.reference
            showingItemNavigatorPopover = false
        }) {
            HStack {
                SwiftUI.Image(systemName: "cube.transparent")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(imageDisplayName(image.reference))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(image.reference)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if selectedImage == image.reference {
                    SwiftUI.Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(selectedImage == image.reference ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var mountPopoverItems: some View {
        ForEach(filteredMounts, id: \.id) { mount in
            mountPopoverRow(mount)
            if mount.id != filteredMounts.last?.id {
                Divider().padding(.leading)
            }
        }
    }

    private func mountPopoverRow(_ mount: ContainerMount) -> some View {
        Button(action: {
            selectedMount = mount.id
            lastSelectedMount = mount.id
            showingItemNavigatorPopover = false
        }) {
            HStack {
                SwiftUI.Image(systemName: "externaldrive")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: mount.mount.source).lastPathComponent)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(mount.mount.source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if selectedMount == mount.id {
                    SwiftUI.Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(selectedMount == mount.id ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func imageDisplayName(_ reference: String) -> String {
        reference.split(separator: "/").last?.split(separator: ":").first.map(String.init) ?? reference
    }

    private var dnsPopoverItems: some View {
        ForEach(containerService.dnsDomains) { domain in
            dnsPopoverRow(domain)
        }
    }

    private func dnsPopoverRow(_ domain: DNSDomain) -> some View {
        Button(action: {
            selectedDNSDomain = domain.domain
            lastSelectedDNSDomain = domain.domain
            showingItemNavigatorPopover = false
        }) {
            HStack {
                SwiftUI.Image(systemName: "network")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(domain.domain)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if selectedDNSDomain == domain.domain {
                    SwiftUI.Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(selectedDNSDomain == domain.domain ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }












    private var containersList: some View {
        VStack(spacing: 0) {

            // Container list
            List(selection: $selectedContainer) {
                ForEach(filteredContainers, id: \.configuration.id) { container in
                    ContainerRow(
                        container: container,
                        isLoading: containerService.loadingContainers.contains(
                            container.configuration.id),
                        stopContainer: { id in
                            Task { @MainActor in
                                await containerService.stopContainer(id)
                            }
                        },
                        startContainer: { id in
                            Task { @MainActor in
                                await containerService.startContainer(id)
                            }
                        },
                        removeContainer: { id in
                            Task { @MainActor in
                                await containerService.removeContainer(id)
                            }
                        },
                        openTerminal: { id in
                            containerService.openTerminal(for: id)
                        },
                        openTerminalBash: { id in
                            containerService.openTerminalWithBash(for: id)
                        }
                    )
                    .tag(container.configuration.id)
                }
            }
            .listStyle(PlainListStyle())
            .animation(.easeInOut(duration: 0.3), value: containerService.containers)
            .focused($listFocusedTab, equals: .containers)
            .onChange(of: selectedContainer) { _, newValue in
                lastSelectedContainer = newValue
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .containers {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        listFocusedTab = .containers
                    }
                } else if newTab == .dns {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        listFocusedTab = .dns
                    }
                    // Load DNS domains when switching to DNS tab
                    Task {
                        await containerService.loadDNSDomains()
                    }
                }
            }

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5)
                .transaction { transaction in
                    transaction.animation = nil
                }

            VStack(alignment: .leading) {

                Toggle("Only show running containers", isOn: $showOnlyRunning)
                    .toggleStyle(CheckboxToggleStyle())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                HStack {
                    SwiftUI.Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter containers...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
        }
    }

    private var filteredContainers: [Container] {
        var filtered = containerService.containers

        // Apply running filter
        if showOnlyRunning {
            filtered = filtered.filter { $0.status.lowercased() == "running" }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { container in
                container.configuration.id.localizedCaseInsensitiveContains(searchText)
                    || container.status.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    private var imagesList: some View {
        VStack(spacing: 0) {
            // Images list
            List(selection: $selectedImage) {
                ForEach(filteredImages, id: \.reference) { image in
                    ContainerImageRow(image: image)
                        .tag(image.reference)
                }
            }
            .listStyle(PlainListStyle())
            .animation(.easeInOut(duration: 0.3), value: containerService.images)
            .focused($listFocusedTab, equals: .images)
            .onChange(of: selectedImage) { _, newValue in
                lastSelectedImage = newValue
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .images {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        listFocusedTab = .images
                    }
                }
            }



            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5)
                .transaction { transaction in
                    transaction.animation = nil
                }

            // Filter controls at bottom
            VStack(alignment: .leading, spacing: 12) {
                // Search & Download button
                Button(action: {
                    showImageSearch = true
                }) {
                    HStack {
                        SwiftUI.Image(systemName: "arrow.down.circle.fill")
                            .font(.body)
                        Text("Search & Download Images")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showImageSearch) {
                    ImageSearchView()
                        .environmentObject(containerService)
                        .frame(minWidth: 700, minHeight: 500)
                    }



                Toggle("Only show images in use", isOn: $showOnlyImagesInUse)
                    .toggleStyle(CheckboxToggleStyle())
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Search field
                HStack {
                    SwiftUI.Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter images...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
        }
    }

    private var filteredImages: [ContainerImage] {
        var filtered = containerService.images

        // Apply "in use" filter
        if showOnlyImagesInUse {
            filtered = filtered.filter { image in
                containerService.containers.contains { container in
                    container.configuration.image.reference == image.reference
                }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { image in
                image.reference.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    @ViewBuilder
    private var detailView: some View {
        // Check if we're in settings mode (no selections)
        let isSettingsMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil

        if isInIntentionalSettingsMode || (isSettingsMode && (selectedTab == .containers || selectedTab == .images || selectedTab == .mounts)) {
            settingsDetailView
        } else {
            switch selectedTab {
            case .containers:
                containerDetailView
            case .images:
                imageDetailView
            case .mounts:
                mountDetailView
            case .dns:
                if let selectedDNSDomain = selectedDNSDomain {
                    dnsDetailView(domain: selectedDNSDomain)
                } else {
                    Text("Select a DNS domain")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .registries:
                registriesDetailView
            case .systemLogs:
                EmptyView()
            }
        }
    }

    private var registriesDetailView: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Registries cannot be listed due to limitations with container itself. To add them, you'll need to open a terminal and run the container commands. Copy your registry password to your clipboard and run:")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("pbpaste | container registry login REGISTRY_URL --username YOUR_USERNAME --password-stdin")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("pbpaste | container registry login REGISTRY_URL --username YOUR_USERNAME --password-stdin", forType: .string)
                            }) {
                                SwiftUI.Image(systemName: "doc.on.clipboard")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy command to clipboard")
                        }
                    }
                }
                Spacer()
            }
            .frame(minHeight: 200)
            .padding()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsDetailView: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Background Refresh Setting
                HStack(alignment: .top) {
                    Text("Refresh Interval:")
                        .frame(width: 220, alignment: .trailing)
                        .padding(.top, 4)

                    VStack(alignment: .leading) {
                        Picker("", selection: Binding(
                            get: { containerService.refreshInterval },
                            set: { containerService.setRefreshInterval($0) }
                        )) {
                            ForEach(ContainerService.RefreshInterval.allCases, id: \.self) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200, alignment: .leading)

                        Text("The frequency that the app will check for updates from containers. Lower intervals increase responsiveness but add system load.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.leading, 10)
                    }

                    Spacer()
                }

                // Software Updates Section
                VStack(spacing: 15) {
                    HStack(alignment: .top) {
                        Text("Updates:")
                            .frame(width: 220, alignment: .trailing)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            if containerService.isCheckingForUpdates {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Checking for updates...")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 10)
                                }
                            } else if containerService.updateAvailable {
                                Button("Download Update") {
                                    containerService.openReleasesPage()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Text("Update available: v\(containerService.latestVersion ?? "")")
                                    .foregroundColor(.green)
                                    .padding(.leading, 10)

                            } else {
                                Button("Check for Updates") {
                                    Task { await containerService.checkForUpdates() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Text("Orchard is up to date (v\(containerService.currentVersion))")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 10)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func dnsDetailView(domain: String) -> some View {
        if let dnsDomain = containerService.dnsDomains.first(where: { $0.domain == domain }) {
            VStack(alignment: .leading, spacing: 20) {
                Text("DNS Domain: \(dnsDomain.domain)")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Containers using this domain
                VStack(alignment: .leading, spacing: 12) {
                    Text("Containers using this domain")
                        .font(.headline)

                    let containersUsingDomain = containerService.containers.filter { container in
                        // Check if container's DNS domain matches
                        if let containerDomain = container.configuration.dns.domain {
                            return containerDomain == dnsDomain.domain
                        }
                        // Also check search domains as fallback
                        return container.configuration.dns.searchDomains.contains(dnsDomain.domain)
                    }

                    if containersUsingDomain.isEmpty {
                        Text("No containers are using this domain")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Text("Container")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("Status")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 100, alignment: .leading)

                                Text("Network")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 120, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor))

                            Divider()

                            // Container rows
                            ForEach(containersUsingDomain, id: \.configuration.id) { container in
                                HStack {
                                    // Container name (clickable)
                                    Button(action: {
                                        selectedTab = .containers
                                        selectedContainer = container.configuration.id
                                    }) {
                                        HStack {
                                            SwiftUI.Image(systemName: "cube.box")
                                                .foregroundColor(container.status.lowercased() == "running" ? .green : .gray)
                                            Text(container.configuration.id)
                                                .foregroundColor(.primary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    // Status
                                    HStack {
                                        Circle()
                                            .fill(container.status.lowercased() == "running" ? .green : .gray)
                                            .frame(width: 8, height: 8)
                                        Text(container.status)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: 100, alignment: .leading)

                                    // Network
                                    Group {
                                        if !container.networks.isEmpty {
                                            Text(container.networks[0].address.replacingOccurrences(of: "/24", with: ""))
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("No network")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(width: 120, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.clear)

                                if container.configuration.id != containersUsingDomain.last?.configuration.id {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(minHeight: 100)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Actions")
                        .font(.headline)

                    Button("Delete Domain") {
                        confirmDNSDomainDeletion(domain: dnsDomain.domain)
                    }
                    .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("Domain not found")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }



    private func confirmDNSDomainDeletion(domain: String) {
        let alert = NSAlert()
        alert.messageText = "Delete DNS Domain"
        alert.informativeText = "Are you sure you want to delete '\(domain)'? This requires administrator privileges."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { await containerService.deleteDNSDomain(domain) }
        }
    }

    private func isValidDomainName(_ domain: String) -> Bool {
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        return predicate.evaluate(with: domain)
    }

    @ViewBuilder
    private var containerDetailView: some View {
        ForEach(containerService.containers, id: \.configuration.id) { container in
            if selectedContainer == container.configuration.id {
                ContainerDetailView(
                    container: container,
                    initialSelectedTab: lastSelectedContainerTab,
                    onTabChanged: { newTab in
                        lastSelectedContainerTab = newTab
                    }
                )
                .environmentObject(containerService)
            }
        }
    }

    @ViewBuilder
    private var imageDetailView: some View {
        ForEach(containerService.images, id: \.reference) { image in
            if selectedImage == image.reference {
                ContainerImageDetailView(
                    image: image,
                    initialSelectedTab: lastSelectedImageTab,
                    onTabChanged: { newTab in
                        lastSelectedImageTab = newTab
                    }
                )
                .environmentObject(containerService)
            }
        }
    }

    private var mountsList: some View {
        VStack(spacing: 0) {
            // Mounts list
            List(selection: $selectedMount) {
                ForEach(filteredMounts, id: \.id) { mount in
                    MountRow(mount: mount)
                        .tag(mount.id)
                }
            }
            .listStyle(PlainListStyle())
            .animation(.easeInOut(duration: 0.3), value: containerService.allMounts)
            .focused($listFocusedTab, equals: .mounts)
            .onChange(of: selectedMount) { _, newValue in
                lastSelectedMount = newValue
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .mounts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        listFocusedTab = .mounts
                    }
                }
            }

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5)
                .transaction { transaction in
                    transaction.animation = nil
                }

            // Filter controls at bottom
            VStack(spacing: 12) {
                // Search field
                HStack {
                    SwiftUI.Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter mounts...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
        }
    }

    private var filteredMounts: [ContainerMount] {
        var filtered = containerService.allMounts

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { mount in
                mount.mount.source.localizedCaseInsensitiveContains(searchText)
                    || mount.mount.destination.localizedCaseInsensitiveContains(searchText)
                    || mount.mountType.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    @ViewBuilder
    private var mountDetailView: some View {
        ForEach(containerService.allMounts, id: \.id) { mount in
            if selectedMount == mount.id {
                MountDetailView(
                    mount: mount,
                    initialSelectedTab: lastSelectedMountTab,
                    onTabChanged: { newTab in
                        lastSelectedMountTab = newTab
                    }
                )
                .environmentObject(containerService)
            }
        }
    }
}

struct AddDNSDomainView: View {
    @EnvironmentObject var containerService: ContainerService
    @Environment(\.dismiss) private var dismiss
    @State private var domainName: String = ""
    @State private var isCreating: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add DNS Domain")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )

            // Content
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Domain Name")
                        .font(.headline)

                    TextField("e.g., local.dev, myapp.local", text: $domainName)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 32)

                    Text("Enter a domain name for local container networking. This requires administrator privileges.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Domain") {
                    createDomain()
                }
                .buttonStyle(.borderedProminent)
                .disabled(domainName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .top
            )
        }
        .frame(width: 500, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func createDomain() {
        let trimmedDomain = domainName.trimmingCharacters(in: .whitespaces)

        guard !trimmedDomain.isEmpty else { return }
        guard isValidDomainName(trimmedDomain) else {
            containerService.errorMessage = "Invalid domain name format."
            return
        }

        isCreating = true

        Task {
            await containerService.createDNSDomain(trimmedDomain)

            await MainActor.run {
                isCreating = false
                if containerService.errorMessage == nil {
                    dismiss()
                }
            }
        }
    }

    private func isValidDomainName(_ domain: String) -> Bool {
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        return predicate.evaluate(with: domain)
    }
}

#Preview {
    ContentView()
        .environmentObject(ContainerService())
}
