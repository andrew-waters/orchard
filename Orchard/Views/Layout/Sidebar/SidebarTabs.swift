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
    let containerService: ContainerService

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
                            if selectedContainer == nil, let firstContainer = containerService.containers.first {
                                selectedContainer = firstContainer.configuration.id
                            }
                        case .images:
                            if selectedImage == nil, let firstImage = containerService.images.first {
                                selectedImage = firstImage.reference
                            }
                        case .mounts:
                            if selectedMount == nil, let firstMount = containerService.allMounts.first {
                                selectedMount = firstMount.id
                            }
                        case .dns:
                            if selectedDNSDomain == nil, let firstDomain = containerService.dnsDomains.first {
                                selectedDNSDomain = firstDomain.domain
                            }
                        case .networks:
                            if selectedNetwork == nil, let firstNetwork = containerService.networks.first {
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
}
