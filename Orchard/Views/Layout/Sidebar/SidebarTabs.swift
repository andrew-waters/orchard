import SwiftUI

struct SidebarTabs: View {
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @Binding var selectedImage: String?
    @Binding var selectedMount: String?
    @Binding var selectedDNSDomain: String?
    @Binding var selectedNetwork: String?
    @Binding var isInIntentionalConfigurationMode: Bool
    @FocusState.Binding var listFocusedTab: TabSelection?
    let isWindowFocused: Bool
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    @EnvironmentObject var dnsService: DNSService
    @EnvironmentObject var networkService: NetworkService

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(TabSelection.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab

                        // Always select first item for tabs with second columns
                        if isInIntentionalConfigurationMode {
                            isInIntentionalConfigurationMode = false
                        }

                        switch tab {
                        case .containers:
                            if selectedContainer == nil, let firstContainer = containerListService.containers.first {
                                selectedContainer = firstContainer.configuration.id
                            }
                        case .images:
                            if selectedImage == nil, let firstImage = imageService.images.first {
                                selectedImage = firstImage.reference
                            }
                        case .mounts:
                            if selectedMount == nil, let firstMount = containerListService.allMounts.first {
                                selectedMount = firstMount.id
                            }
                        case .dns:
                            if selectedDNSDomain == nil, let firstDomain = dnsService.dnsDomains.first {
                                selectedDNSDomain = firstDomain.domain
                            }
                        case .networks:
                            if selectedNetwork == nil, let firstNetwork = networkService.networks.first {
                                selectedNetwork = firstNetwork.id
                            }
                        case .registries, .systemLogs, .stats, .configuration:
                            // Clear all selections for tabs without second columns
                            selectedContainer = nil
                            selectedImage = nil
                            selectedMount = nil
                            selectedDNSDomain = nil
                            selectedNetwork = nil
                            if tab == .configuration {
                                isInIntentionalConfigurationMode = true
                            }
                            break
                        }

                        // Set focus after state changes
                        listFocusedTab = nil
                        DispatchQueue.main.async {
                            switch tab {
                            case .containers, .images, .mounts, .dns, .networks:
                                self.listFocusedTab = tab
                            case .registries, .systemLogs, .stats, .configuration:
                                self.listFocusedTab = nil
                            }
                        }
                    }) {
                        let isConfigurationMode = selectedContainer == nil && selectedImage == nil && selectedMount == nil && selectedDNSDomain == nil && selectedNetwork == nil
                        let isActiveTab = selectedTab == tab && !isConfigurationMode && !isInIntentionalConfigurationMode

                        SwiftUI.Image(systemName: tab.icon)
                            .font(.system(size: 14))
                            .foregroundColor(isActiveTab ? (isWindowFocused ? .accentColor : .secondary) : (isWindowFocused ? .secondary : Color.secondary.opacity(0.5)))
                            .frame(width: 32, height: 32)
                            .background(
                                isActiveTab ? Color.accentColor.opacity(isWindowFocused ? 0.15 : 0.08) : Color.clear
                            )
                            .cornerRadius(6)
                            .overlay(alignment: .topTrailing) {
                                if let count = badgeCount(for: tab), count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 15, minHeight: 15)
                                        .background(Capsule().fill(Color.secondary))
                                        .overlay(Capsule().strokeBorder(Color(NSColor.controlBackgroundColor), lineWidth: 1.5))
                                        .offset(x: 7, y: -5)
                                        .allowsHitTesting(false)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .accessibilityIdentifier("tab-\(tab.rawValue)")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    /// Ambient count shown on a tab's icon. Running-count for containers (the active
    /// subset), plain inventory counts for the resource tabs. Returns nil for tabs
    /// that have no meaningful count. A count of 0 hides the badge (handled by caller).
    private func badgeCount(for tab: TabSelection) -> Int? {
        switch tab {
        case .containers:
            return containerListService.containers.filter { $0.status.lowercased() == "running" }.count
        case .images:
            return imageService.images.count
        case .mounts:
            return containerListService.allMounts.count
        case .dns:
            return dnsService.dnsDomains.count
        case .networks:
            return networkService.networks.count
        case .registries, .systemLogs, .stats, .configuration:
            return nil
        }
    }
}
