import AppKit
import SwiftUI

// MARK: - Container Detail Views

struct ContainerDetailView: View {
    let container: Container
    let initialSelectedTab: String
    let onTabChanged: (String) -> Void
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedTab: ContainerTab = .overview
    @State private var showEditConfiguration = false

    enum ContainerTab: String, CaseIterable {
        case overview = "Overview"
        case network = "Network"
        case environment = "Environment"
        case mounts = "Mounts"
        case labels = "Labels"
        case logs = "Logs"

        var systemImage: String {
            switch self {
            case .overview:
                return "info.circle"
            case .network:
                return "network"
            case .environment:
                return "gearshape"
            case .mounts:
                return "externaldrive"
            case .labels:
                return "tag"
            case .logs:
                return "doc.text"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabPickerSection
            tabContentSection
        }
        .onAppear {
            selectedTab = tabFromString(initialSelectedTab)
        }
        .sheet(isPresented: $showEditConfiguration) {
            EditContainerView(container: container)
                .environmentObject(containerService)
        }
    }

    private var tabPickerSection: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(ContainerTab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
                Spacer()
                
                // Edit Configuration button - only for stopped containers
                if container.status.lowercased() != "running" {
                    Button(action: {
                        showEditConfiguration = true
                    }) {
                        HStack(spacing: 6) {
                            SwiftUI.Image(systemName: "pencil.circle")
                            Text("Edit Configuration")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
        }
    }

    private func tabButton(for tab: ContainerTab) -> some View {
        Button(action: {
            selectedTab = tab
            onTabChanged(tab.rawValue)
        }) {
            HStack {
                SwiftUI.Image(systemName: tab.systemImage)
                Text(tab.rawValue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear
            )
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var tabContentSection: some View {
        Group {
            switch selectedTab {
            case .overview:
                containerOverviewTab
            case .network:
                containerNetworkTab
            case .environment:
                containerEnvironmentTab
            case .mounts:
                containerMountsTab
            case .labels:
                containerLabelsTab
            case .logs:
                LogsView(containerId: container.configuration.id)
                    .environmentObject(containerService)
            }
        }
    }

    private var containerOverviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Overview and Image side by side
                HStack(alignment: .top, spacing: 20) {
                    containerOverviewSection(container: container)
                    containerImageSection(container: container)
                }

                Divider()

                // Resources and Process side by side
                HStack(alignment: .top, spacing: 20) {
                    containerResourcesSection(container: container)
                    containerProcessSection(container: container)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    private var containerNetworkTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                containerNetworkSection(container: container)
                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    private var containerEnvironmentTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                containerEnvironmentSection(container: container)
                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    private var containerMountsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                containerMountsSection(container: container)
            }
            .padding()
        }
    }

    private var containerLabelsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                containerLabelsSection(container: container)
            }
            .padding()
        }
    }

    // MARK: - Detail Sections

    private func containerOverviewSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                CopyableInfoRow(label: "Container ID", value: container.configuration.id)
                InfoRow(label: "Runtime", value: container.configuration.runtimeHandler)
                InfoRow(
                    label: "Platform",
                    value:
                        "\(container.configuration.platform.os)/\(container.configuration.platform.architecture)"
                )
                if let hostname = container.configuration.hostname {
                    InfoRow(label: "Hostname", value: hostname)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func containerImageSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                NavigableInfoRow(
                    label: "Reference",
                    value: container.configuration.image.reference,
                    onNavigate: {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToImage"),
                            object: container.configuration.image.reference
                        )
                    }
                )
                InfoRow(
                    label: "Media Type", value: container.configuration.image.descriptor.mediaType)
                CopyableInfoRow(
                    label: "Digest",
                    value: String(
                        container.configuration.image.descriptor.digest.replacingOccurrences(
                            of: "sha256:", with: ""
                        ).prefix(12)),
                    copyValue: container.configuration.image.descriptor.digest
                )
                InfoRow(
                    label: "Size",
                    value: ByteCountFormatter().string(
                        fromByteCount: Int64(container.configuration.image.descriptor.size)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func containerNetworkSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network")
                .font(.headline)
                .foregroundColor(.primary)

            if !container.networks.isEmpty {
                ForEach(container.networks, id: \.hostname) { network in
                    VStack(alignment: .leading, spacing: 8) {
                        let addressValue = network.address.replacingOccurrences(of: "/24", with: "")
                        CopyableInfoRow(
                            label: "Address",
                            value: network.address,
                            copyValue: addressValue
                        )
                        InfoRow(label: "Gateway", value: network.gateway)
                        InfoRow(label: "Network", value: network.network)
                        if network.hostname != container.configuration.hostname {
                            InfoRow(label: "Hostname", value: network.hostname)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }

                // DNS Configuration
                if !container.configuration.dns.nameservers.isEmpty
                    || !container.configuration.dns.searchDomains.isEmpty
                {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DNS Configuration")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if !container.configuration.dns.nameservers.isEmpty {
                            InfoRow(
                                label: "Nameservers",
                                value: container.configuration.dns.nameservers.joined(
                                    separator: ", "))
                        }
                        if !container.configuration.dns.searchDomains.isEmpty {
                            InfoRow(
                                label: "Search Domains",
                                value: container.configuration.dns.searchDomains.joined(
                                    separator: ", "))
                        }
                        if !container.configuration.dns.options.isEmpty {
                            InfoRow(
                                label: "Options",
                                value: container.configuration.dns.options.joined(separator: ", "))
                        }
                    }
                }
            } else {
                Text("No network configuration")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    private func containerResourcesSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resources")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "CPUs", value: "\(container.configuration.resources.cpus)")
                InfoRow(
                    label: "Memory",
                    value: ByteCountFormatter().string(
                        fromByteCount: Int64(container.configuration.resources.memoryInBytes)))
                InfoRow(
                    label: "Rosetta",
                    value: container.configuration.rosetta ? "Enabled" : "Disabled")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func containerProcessSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Process Configuration")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Executable", value: container.configuration.initProcess.executable)
                InfoRow(
                    label: "Working Directory",
                    value: container.configuration.initProcess.workingDirectory)
                InfoRow(
                    label: "Terminal",
                    value: container.configuration.initProcess.terminal ? "Enabled" : "Disabled")

                if !container.configuration.initProcess.arguments.isEmpty {
                    InfoRow(
                        label: "Arguments",
                        value: container.configuration.initProcess.arguments.joined(separator: " "))
                }

                // User information
                if let userString = container.configuration.initProcess.user.raw?.userString {
                    InfoRow(label: "User", value: userString)
                }
                if let userId = container.configuration.initProcess.user.id {
                    InfoRow(label: "UID:GID", value: "\(userId.uid):\(userId.gid)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func containerEnvironmentSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environment Variables")
                .font(.headline)
                .foregroundColor(.primary)

            if !container.configuration.initProcess.environment.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(container.configuration.initProcess.environment, id: \.self) {
                            envVar in
                            let components = envVar.split(separator: "=", maxSplits: 1)
                            if components.count == 2 {
                                HStack(alignment: .top) {
                                    Text(String(components[0]))
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .frame(minWidth: 100, alignment: .leading)

                                    Text("=")
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    Text(String(components[1]))
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 2)
                            } else {
                                Text(envVar)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                Text("No environment variables")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    private func containerMountsSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mounts")
                .font(.headline)
                .foregroundColor(.primary)

            if !container.configuration.mounts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(container.configuration.mounts.enumerated()), id: \.offset) {
                        index, mount in
                        Button(action: {
                            // Navigate to mount details
                            let mountId = "\(mount.source)->\(mount.destination)"
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToMount"),
                                object: mountId
                            )
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Mount \(index + 1)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Spacer()

                                    SwiftUI.Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                InfoRow(label: "Source", value: mount.source)
                                InfoRow(label: "Destination", value: mount.destination)

                                if mount.type.virtiofs != nil {
                                    InfoRow(label: "Type", value: "VirtioFS")
                                } else if mount.type.tmpfs != nil {
                                    InfoRow(label: "Type", value: "tmpfs")
                                } else {
                                    InfoRow(label: "Type", value: "Unknown")
                                }

                                if !mount.options.isEmpty {
                                    InfoRow(
                                        label: "Options", value: mount.options.joined(separator: ", "))
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("View mount details")
                    }
                }
            } else {
                Text("No mounts")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    private func containerLabelsSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Labels")
                .font(.headline)
                .foregroundColor(.primary)

            if let labels = container.configuration.labels, !labels.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(labels.keys.sorted()), id: \.self) { key in
                            HStack(alignment: .top) {
                                Text(key)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(minWidth: 100, alignment: .leading)

                                Text("=")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text(labels[key] ?? "")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                Text("No labels")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    // Helper function to convert string to enum
    private func tabFromString(_ tabString: String) -> ContainerTab {
        return ContainerTab.allCases.first { $0.rawValue == tabString } ?? .overview
    }
}

// MARK: - Container Image Detail View

struct ContainerImageDetailView: View {
    let image: ContainerImage
    let initialSelectedTab: String
    let onTabChanged: (String) -> Void
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedTab: ImageTab = .overview
    @State private var showRunContainer = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    enum ImageTab: String, CaseIterable {
        case overview = "Overview"
        case inUseBy = "In Use By"

        var systemImage: String {
            switch self {
            case .overview:
                return "info.circle"
            case .inUseBy:
                return "cube.box"
            }
        }
    }

    private var imageName: String {
        let components = image.reference.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent.split(separator: ":").first ?? lastComponent)
        }
        return image.reference
    }

    private var imageTag: String {
        if let tagComponent = image.reference.split(separator: ":").last,
            tagComponent != image.reference.split(separator: "/").last
        {
            return String(tagComponent)
        }
        return "latest"
    }

    private var createdDate: String? {
        image.descriptor.annotations?["org.opencontainers.image.created"]
    }

    private var containersUsingImage: [Container] {
        containerService.containers.filter { container in
            container.configuration.image.reference == image.reference
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabPickerSection
            tabContentSection
        }
        .onAppear {
            selectedTab = imageTabFromString(initialSelectedTab)
        }
        .sheet(isPresented: $showRunContainer) {
            RunContainerView(imageName: image.reference)
                .environmentObject(containerService)
        }
    }

    // Helper function to convert string to enum
    private func imageTabFromString(_ tabString: String) -> ImageTab {
        return ImageTab.allCases.first { $0.rawValue == tabString } ?? .overview
    }

    private var tabPickerSection: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(ImageTab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
                Spacer()
                
                // Run Container button
                Button(action: {
                    showRunContainer = true
                }) {
                    HStack(spacing: 6) {
                        SwiftUI.Image(systemName: "play.circle.fill")
                        Text("Run Container")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDeleting)
                
                // Delete Image button - only show if no containers are using it
                if containersUsingImage.isEmpty {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack(spacing: 6) {
                            if isDeleting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                SwiftUI.Image(systemName: "trash")
                            }
                            Text(isDeleting ? "Deleting..." : "Delete")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(isDeleting)
                    .alert("Delete Image?", isPresented: $showDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete", role: .destructive) {
                            deleteImage()
                        }
                    } message: {
                        Text("Are you sure you want to delete '\(imageName)'? This action cannot be undone.")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
        }
    }

    private func tabButton(for tab: ImageTab) -> some View {
        Button(action: {
            selectedTab = tab
            onTabChanged(tab.rawValue)
        }) {
            HStack {
                SwiftUI.Image(systemName: tab.systemImage)
                Text(tab.rawValue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear
            )
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var tabContentSection: some View {
        ScrollView {
            Group {
                switch selectedTab {
                case .overview:
                    imageOverviewTab
                case .inUseBy:
                    imageInUseByTab
                }
            }
            .padding()
        }
    }

    private var imageOverviewTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                // Overview section
                imageOverviewSection()

                Divider()

                // Technical details section
                imageTechnicalSection()

                Divider()

            }

            if let annotations = image.descriptor.annotations, !annotations.isEmpty {
                Divider()

                // Annotations section
                imageAnnotationsSection(annotations: annotations)
            }

            Spacer(minLength: 20)
        }
    }

    private var imageInUseByTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            containersUsingImageSection()
            Spacer(minLength: 20)
        }
    }

    // MARK: - Detail Sections

    private func imageOverviewSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                CopyableInfoRow(label: "Reference", value: image.reference)
                InfoRow(label: "Name", value: imageName)
                InfoRow(label: "Tag", value: imageTag)
                InfoRow(
                    label: "Size",
                    value: ByteCountFormatter().string(fromByteCount: Int64(image.descriptor.size)))
                if let created = createdDate {
                    InfoRow(label: "Created", value: formatDate(created))
                }
            }
        }
    }

    private func imageTechnicalSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technical Details")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Media Type", value: image.descriptor.mediaType)
                CopyableInfoRow(
                    label: "Digest",
                    value: String(
                        image.descriptor.digest.replacingOccurrences(of: "sha256:", with: "")
                            .prefix(12)),
                    copyValue: image.descriptor.digest
                )
                InfoRow(label: "Size (bytes)", value: "\(image.descriptor.size)")
            }
        }
    }

    private func containersUsingImageSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if containersUsingImage.isEmpty {
                Text("No containers are currently using this image")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(containersUsingImage, id: \.configuration.id) { container in
                        ContainerImageUsageRow(container: container)
                    }
                }
            }
        }
    }

    private func imageAnnotationsSection(annotations: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Annotations")
                .font(.headline)
                .foregroundColor(.primary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(annotations.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(minWidth: 150, alignment: .leading)

                            Text(value)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            CopyButton(text: value, label: "Copy value")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 200)
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }

    // MARK: - Helper Methods

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func deleteImage() {
        isDeleting = true
        
        Task {
            await containerService.deleteImage(image.reference)
            
            await MainActor.run {
                isDeleting = false
            }
        }
    }
}

//struct CopyButton: View {
//    let text: String
//    let label: String
//    @State private var showingFeedback = false
//
//    var body: some View {
//        Button {
//            let pasteboard = NSPasteboard.general
//            pasteboard.clearContents()
//            pasteboard.setString(text, forType: .string)
//
//            showingFeedback = true
//            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//                showingFeedback = false
//            }
//        } label: {
//            SwiftUI.Image(systemName: showingFeedback ? "checkmark" : "doc.on.doc")
//                .font(.caption)
//                .foregroundColor(showingFeedback ? .white : .secondary)
//                .background(showingFeedback ? Color.green : Color.clear)
//                .clipShape(Circle())
//        }
//        .buttonStyle(.plain)
//        .help(label)
//    }
//}

struct ContainerImageUsageRow: View {
    let container: Container
    @Environment(\.openURL) var openURL
    @State private var copyFeedbackStates: [String: Bool] = [:]

    private var networkAddress: String {
        guard !container.networks.isEmpty else {
            return "No network"
        }
        return container.networks[0].address.replacingOccurrences(of: "/24", with: "")
    }

    var body: some View {
        Button(action: {
            // This will trigger navigation to the container detail view
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToContainer"),
                object: container.configuration.id
            )
        }) {
            HStack {
                Circle()
                    .fill(container.status.lowercased() == "running" ? .green : .gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.configuration.id)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack {
                        if !container.networks.isEmpty {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(networkAddress)
                                .font(.caption)
                                .monospaced()
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                SwiftUI.Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to view container details")
        .contextMenu {
            Button {
                copyToClipboard(container.configuration.id, key: "containerID")
            } label: {
                HStack {
                    SwiftUI.Image(systemName: copyFeedbackStates["containerID"] == true ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copyFeedbackStates["containerID"] == true ? .white : .primary)
                    Text("Copy Container ID")
                }
                .background(copyFeedbackStates["containerID"] == true ? Color.green : Color.clear)
            }

            if !container.networks.isEmpty {
                Button {
                    copyToClipboard(networkAddress, key: "networkAddress")
                } label: {
                    HStack {
                        SwiftUI.Image(systemName: copyFeedbackStates["networkAddress"] == true ? "checkmark" : "network")
                            .foregroundColor(copyFeedbackStates["networkAddress"] == true ? .white : .primary)
                        Text("Copy IP Address")
                    }
                    .background(copyFeedbackStates["networkAddress"] == true ? Color.green : Color.clear)
                }
            }
        }
    }

    private func copyToClipboard(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyFeedbackStates[key] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyFeedbackStates[key] = false
        }
    }
}

struct MountDetailView: View {
    let mount: ContainerMount
    let initialSelectedTab: String
    let onTabChanged: (String) -> Void
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedTab: MountTab = .overview

    enum MountTab: String, CaseIterable {
        case overview = "Overview"
        case inUseBy = "In Use By"

        var systemImage: String {
            switch self {
            case .overview:
                return "info.circle"
            case .inUseBy:
                return "cube.box"
            }
        }
    }

    private var containersUsingMount: [Container] {
        containerService.containers.filter { container in
            mount.containerIds.contains(container.configuration.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabPickerSection
            tabContentSection
        }
        .onAppear {
            selectedTab = mountTabFromString(initialSelectedTab)
        }
    }

    // Helper function to convert string to enum
    private func mountTabFromString(_ tabString: String) -> MountTab {
        return MountTab.allCases.first { $0.rawValue == tabString } ?? .overview
    }

    private var tabPickerSection: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(MountTab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
        }
    }

    private func tabButton(for tab: MountTab) -> some View {
        Button(action: {
            selectedTab = tab
            onTabChanged(tab.rawValue)
        }) {
            HStack {
                SwiftUI.Image(systemName: tab.systemImage)
                Text(tab.rawValue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear
            )
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var tabContentSection: some View {
        ScrollView {
            Group {
                switch selectedTab {
                case .overview:
                    mountOverviewTab
                case .inUseBy:
                    mountInUseByTab
                }
            }
            .padding()
        }
    }

    private var mountOverviewTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            mountOverviewSection()
            mountTechnicalSection()
            Spacer(minLength: 20)
        }
    }

    private var mountInUseByTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            containersUsingMountSection()
            Spacer(minLength: 20)
        }
    }

    private func mountOverviewSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                CopyableInfoRow(label: "Source", value: mount.mount.source)
                CopyableInfoRow(label: "Destination", value: mount.mount.destination)
                InfoRow(label: "Type", value: mount.mountType)
                InfoRow(label: "Containers", value: "\(mount.containerIds.count)")

                if !mount.optionsString.isEmpty {
                    InfoRow(label: "Options", value: mount.optionsString)
                }
            }
        }
    }

    private func mountTechnicalSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technical Details")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                if mount.mount.type.virtiofs != nil {
                    InfoRow(label: "Filesystem", value: "VirtioFS")
                } else if mount.mount.type.tmpfs != nil {
                    InfoRow(label: "Filesystem", value: "tmpfs")
                } else {
                    InfoRow(label: "Filesystem", value: "Unknown mount type")
                }

                if !mount.mount.options.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mount Options:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(mount.mount.options, id: \.self) { option in
                            Text("• \(option)")
                                .font(.subheadline)
                                .monospaced()
                                .foregroundColor(.primary)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private func containersUsingMountSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if containersUsingMount.isEmpty {
                Text("No containers are currently using this mount")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(containersUsingMount, id: \.configuration.id) { container in
                        MountContainerUsageRow(container: container)
                    }
                }
            }
        }
    }
}

struct MountContainerUsageRow: View {
    let container: Container
    @Environment(\.openURL) var openURL
    @State private var copyFeedbackStates: [String: Bool] = [:]

    private var networkAddress: String {
        guard !container.networks.isEmpty else {
            return "No network"
        }
        return container.networks[0].address.replacingOccurrences(of: "/24", with: "")
    }

    var body: some View {
        Button(action: {
            // Navigate to container details
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToContainer"),
                object: container.configuration.id
            )
        }) {
            HStack {
                Circle()
                    .fill(container.status.lowercased() == "running" ? .green : .gray)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.configuration.id)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        Text(container.status.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !container.networks.isEmpty {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(networkAddress)
                                .font(.caption)
                                .monospaced()
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                SwiftUI.Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                copyToClipboard(container.configuration.id, key: "containerID")
            } label: {
                HStack {
                    SwiftUI.Image(systemName: copyFeedbackStates["containerID"] == true ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copyFeedbackStates["containerID"] == true ? .white : .primary)
                    Text("Copy Container ID")
                }
                .background(copyFeedbackStates["containerID"] == true ? Color.green : Color.clear)
            }

            if !container.networks.isEmpty {
                Button {
                    copyToClipboard(networkAddress, key: "networkAddress")
                } label: {
                    HStack {
                        SwiftUI.Image(systemName: copyFeedbackStates["networkAddress"] == true ? "checkmark" : "network")
                            .foregroundColor(copyFeedbackStates["networkAddress"] == true ? .white : .primary)
                        Text("Copy IP Address")
                    }
                    .background(copyFeedbackStates["networkAddress"] == true ? Color.green : Color.clear)
                }
            }
        }
        .help("Click to view container details")
    }

    private func copyToClipboard(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyFeedbackStates[key] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyFeedbackStates[key] = false
        }
    }
}
