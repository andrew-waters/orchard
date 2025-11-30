import SwiftUI

struct SidebarTabs: View {
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @Binding var selectedImage: String?
    @Binding var selectedMount: String?
    @Binding var selectedDNSDomain: String?
    @Binding var isInIntentionalSettingsMode: Bool
    let isWindowFocused: Bool
    let containerService: ContainerService

    var body: some View {
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
}
