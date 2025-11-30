import SwiftUI

struct ItemNavigatorPopover: View {
    @EnvironmentObject var containerService: ContainerService
    let selectedTab: TabSelection
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
    @Binding var showingItemNavigatorPopover: Bool
    let showOnlyRunning: Bool
    let showOnlyImagesInUse: Bool
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverHeader
            Divider()
            popoverContent
        }
        .frame(width: 300)
        .background(Color(NSColor.controlBackgroundColor))
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
                case .networks:
                    networkPopoverItems
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
            HStack(spacing: 8) {
                Circle()
                    .fill(container.status.lowercased() == "running" ? .green : .gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.configuration.id)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(container.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedContainer == container.configuration.id {
                    SwiftUI.Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
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
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "cube.transparent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                        .foregroundStyle(Color.accentColor)
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
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "externaldrive")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(selectedMount == mount.id ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "network")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(domain.domain)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if selectedDNSDomain == domain.domain {
                    SwiftUI.Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(selectedDNSDomain == domain.domain ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var networkPopoverItems: some View {
        ForEach(containerService.networks) { network in
            networkPopoverRow(network)
            if network.id != containerService.networks.last?.id {
                Divider().padding(.leading)
            }
        }
    }

    private func networkPopoverRow(_ network: ContainerNetwork) -> some View {
        Button(action: {
            selectedNetwork = network.id
            lastSelectedNetwork = network.id
            showingItemNavigatorPopover = false
        }) {
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "wifi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(network.id)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if !network.config.labels.isEmpty {
                        Text("\(network.config.labels.count) label\(network.config.labels.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No labels")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if selectedNetwork == network.id {
                    SwiftUI.Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(selectedNetwork == network.id ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func imageDisplayName(_ reference: String) -> String {
        reference.split(separator: "/").last?.split(separator: ":").first.map(String.init) ?? reference
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
}
