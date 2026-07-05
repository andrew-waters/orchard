import AppKit
import SwiftUI

// MARK: - Container Detail Views

struct ContainerDetailView: View {
    let container: Container
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    @EnvironmentObject var statsService: StatsService
    @Binding var selectedTabBinding: TabSelection
    @Binding var selectedNetwork: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContainerDetailHeader(container: container)
            Divider()
            content
        }
        .onAppear {
            // The detail view is a stats consumer: the service samples while it's shown, so
            // history accumulates for the charts.
            Task { await statsService.load(showLoading: true) }
            statsService.beginSampling()
        }
        .onDisappear {
            statsService.endSampling()
        }
    }

    // One scrolling page — the former Overview, Environment and Mounts tabs merged.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Stats master–detail; mounts sit beneath the disk stats.
                ContainerStatsPanel(container: container)

                // The rest of the configuration, two per row (paired to balance heights).
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                              GridItem(.flexible(), alignment: .top)],
                    spacing: 12
                ) {
                    sectionWell("Overview") { containerOverviewSection(container: container) }
                    sectionWell("Environment") { containerEnvironmentSection(container: container) }
                    sectionWell("Image") { containerImageSection(container: container) }
                    sectionWell("Process") { containerProcessSection(container: container) }
                    sectionWell("Network") { containerNetworkSection(container: container) }
                    sectionWell("Labels") { containerLabelsSection(container: container) }
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    // MARK: - Detail Sections

    @ViewBuilder
    private func sectionWell<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundColor(.primary)
            content()
        }
        .well()
    }

    private func containerOverviewSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    value: ByteFormat.string(container.configuration.image.descriptor.size))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func containerNetworkSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !container.networks.isEmpty {
                ForEach(container.networks, id: \.hostname) { network in
                    let cleanHostname = network.hostname.hasSuffix(".") ? String(network.hostname.dropLast()) : network.hostname
                    CopyableInfoRow(label: "Hostname", value: cleanHostname, copyValue: cleanHostname)
                    CopyableInfoRow(
                        label: "Address",
                        value: network.address,
                        copyValue: network.address.replacingOccurrences(of: "/24", with: "")
                    )
                    InfoRow(label: "Gateway", value: network.gateway)
                    ClickableInfoRow(
                        label: "Network",
                        value: network.network,
                        onTap: {
                            selectedTabBinding = .networks
                            selectedNetwork = network.network
                        }
                    )
                    if let domain = container.configuration.dns.domain {
                        ClickableInfoRow(
                            label: "Domain",
                            value: domain,
                            onTap: {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("NavigateToDNSDomain"),
                                    object: domain
                                )
                            }
                        )
                    }
                }

                if !container.configuration.publishedPorts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Published Ports").font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                        ForEach(container.configuration.publishedPorts, id: \.containerPort) { port in
                            let portSpec = port.hostAddress != nil ?
                                "\(port.hostAddress!):\(port.hostPort):\(port.containerPort)/\(port.transportProtocol)" :
                                "\(port.hostPort):\(port.containerPort)/\(port.transportProtocol)"
                            CopyableInfoRow(label: "Port", value: portSpec, copyValue: portSpec)
                        }
                    }
                }

                if !container.configuration.dns.nameservers.isEmpty
                    || !container.configuration.dns.searchDomains.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DNS Configuration").font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                        if !container.configuration.dns.nameservers.isEmpty {
                            InfoRow(label: "Nameservers", value: container.configuration.dns.nameservers.joined(separator: ", "))
                        }
                        if !container.configuration.dns.searchDomains.isEmpty {
                            InfoRow(label: "Search Domains", value: container.configuration.dns.searchDomains.joined(separator: ", "))
                        }
                        if !container.configuration.dns.options.isEmpty {
                            InfoRow(label: "Options", value: container.configuration.dns.options.joined(separator: ", "))
                        }
                    }
                }
            } else {
                Text("No network configuration").foregroundColor(.secondary).italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func containerProcessSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
            if !container.configuration.initProcess.environment.isEmpty {
                EnvironmentVariablesTable(environment: container.configuration.initProcess.environment)
            } else {
                Text("No environment variables")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    private func containerLabelsSection(container: Container) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !container.configuration.labels.isEmpty {
                LabelsTable(labels: container.configuration.labels)
            } else {
                Text("No labels")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

}

// MARK: - Environment Variables Table

struct EnvironmentVariablesTable: View {
    let environment: [String]
    @State private var revealedValues: Set<Int> = []

    private var parsedEnvironment: [(key: String, value: String)] {
        environment.compactMap { envVar in
            let components = envVar.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else { return nil }
            return (key: String(components[0]), value: String(components[1]))
        }
    }

    private var maxKeyWidth: CGFloat {
        let keys = parsedEnvironment.map { $0.key }
        let maxKey = keys.max { $0.count < $1.count } ?? ""

        // Approximate character width for monospaced font at subheadline size
        // This is a rough estimation - actual width may vary
        return CGFloat(maxKey.count) * 7.5 + 20 // 7.5 points per character + padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table header
            HStack {
                Text("Variable")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: maxKeyWidth, alignment: .leading)

                Text("Value")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // Table rows
            if parsedEnvironment.isEmpty {
                // Handle malformed environment variables
                ForEach(environment, id: \.self) { envVar in
                    HStack {
                        Text(envVar)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.clear)

                    if envVar != environment.last {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            } else {
                ForEach(Array(parsedEnvironment.enumerated()), id: \.offset) { index, envPair in
                    HStack(alignment: .top, spacing: 0) {
                        // Key column
                        Text(envPair.key)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.primary)
                            .fontWeight(.medium)
                            .frame(width: maxKeyWidth, alignment: .leading)
                            .textSelection(.enabled)

                        // Value column — hidden until revealed, but copyable either way.
                        HStack(alignment: .top, spacing: 8) {
                            if revealedValues.contains(index) {
                                Text(envPair.value)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(nil)
                            } else {
                                Text("••••••••")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Button(revealedValues.contains(index) ? "Hide" : "Show") {
                                if revealedValues.contains(index) {
                                    revealedValues.remove(index)
                                } else {
                                    revealedValues.insert(index)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.blue)
                            Spacer()
                            CopyButton(text: envPair.value, label: "Copy value")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.1))

                    if index < parsedEnvironment.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Labels Table

struct LabelsTable: View {
    let labels: [String: String]

    private var sortedLabels: [(key: String, value: String)] {
        labels.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
    }

    private var maxKeyWidth: CGFloat {
        let keys = sortedLabels.map { $0.key }
        let maxKey = keys.max { $0.count < $1.count } ?? ""

        // Approximate character width for monospaced font at subheadline size
        return CGFloat(maxKey.count) * 7.5 + 20 // 7.5 points per character + padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table header
            HStack {
                Text("Label")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: maxKeyWidth, alignment: .leading)

                Text("Value")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // Table rows
            ForEach(Array(sortedLabels.enumerated()), id: \.offset) { index, labelPair in
                HStack(alignment: .top, spacing: 0) {
                    // Key column
                    Text(labelPair.key)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                        .frame(width: maxKeyWidth, alignment: .leading)
                        .textSelection(.enabled)

                    // Value column
                    Text(labelPair.value)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.1))

                if index < sortedLabels.count - 1 {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Container Image Detail View

struct ContainerImageDetailView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    let image: ContainerImage
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?
    @State private var inspection: ImageInspection?
    @State private var isInspecting: Bool = false

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
        containerListService.containers.filter { container in
            container.configuration.image.reference == image.reference
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ImageDetailHeader(image: image)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        imageOverviewSection()
                        Divider()
                        imageTechnicalSection()
                    }

                    // Image config from inspection
                    if isInspecting {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Inspecting image...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let inspection = inspection {
                        ForEach(Array(inspection.variants.enumerated()), id: \.offset) { _, variant in
                            Divider()
                            imageConfigSection(variant: variant)
                        }
                    }

                    if let annotations = image.descriptor.annotations, !annotations.isEmpty {
                        Divider()
                        imageAnnotationsSection(annotations: annotations)
                    }

                    Divider()
                    containersUsingImageSection()

                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
        .onAppear {
            Task {
                isInspecting = true
                inspection = try? await imageService.inspect(reference: image.reference)
                isInspecting = false
            }
        }
    }

    // MARK: - Detail Sections

    private func imageOverviewSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Reference", value: image.reference)
                InfoRow(label: "Name", value: imageName)
                InfoRow(label: "Tag", value: imageTag)
                InfoRow(
                    label: "Size",
                    value: ByteFormat.string(image.descriptor.size))
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
                InfoRow(
                    label: "Digest",
                    value: String(
                        image.descriptor.digest.replacingOccurrences(of: "sha256:", with: "")
                            .prefix(12))
                )
                InfoRow(label: "Size (bytes)", value: "\(image.descriptor.size)")
            }
        }
    }

    private func imageConfigSection(variant: ImageInspection.Variant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configuration")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("(\(variant.platform))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(ByteFormat.string(variant.size))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let entrypoint = variant.entrypoint, !entrypoint.isEmpty {
                    InfoRow(label: "Entrypoint", value: entrypoint.joined(separator: " "))
                }

                if let cmd = variant.cmd, !cmd.isEmpty {
                    InfoRow(label: "Cmd", value: cmd.joined(separator: " "))
                }

                if let workingDir = variant.workingDir, !workingDir.isEmpty {
                    InfoRow(label: "Working Dir", value: workingDir)
                }

                if let user = variant.user, !user.isEmpty {
                    InfoRow(label: "User", value: user)
                }

                if let ports = variant.exposedPorts, !ports.isEmpty {
                    InfoRow(label: "Exposed Ports", value: ports.joined(separator: ", "))
                }

                if let volumes = variant.volumes, !volumes.isEmpty {
                    InfoRow(label: "Volumes", value: volumes.joined(separator: ", "))
                }
            }

            if let env = variant.env, !env.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(env, id: \.self) { envVar in
                                let parts = envVar.split(separator: "=", maxSplits: 1)
                                HStack(alignment: .top, spacing: 4) {
                                    Text(String(parts.first ?? ""))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Text("=")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(String(parts.count > 1 ? parts[1] : ""))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                }
            }
        }
    }

    private func containersUsingImageSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Used By Containers")
                .font(.headline)
                .foregroundColor(.primary)

            ContainerTable(
                containers: containersUsingImage,
                selectedTab: $selectedTab,
                selectedContainer: $selectedContainer,
                emptyStateMessage: "No containers are currently using this image"
            )
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
}

struct ClickableInfoRow: View {
    let label: String
    let value: String
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Button(value) {
                onTap()
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .monospaced()
            .foregroundColor(.accentColor)
            .help("Click to open in browser")

            Spacer()
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
    @EnvironmentObject var containerListService: ContainerListService
    let mount: ContainerMount
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    private var containersUsingMount: [Container] {
        containerListService.containers.filter { container in
            mount.containerIds.contains(container.configuration.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MountDetailHeader(mount: mount)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mountOverviewSection()
                    mountTechnicalSection()
                    containersUsingMountSection()
                    Spacer(minLength: 20)
                }
                .padding()
            }
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
            Text("Used By Containers")
                .font(.headline)
                .foregroundColor(.primary)

            ContainerTable(
                containers: containersUsingMount,
                selectedTab: $selectedTab,
                selectedContainer: $selectedContainer,
                emptyStateMessage: "No containers are currently using this mount"
            )
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
