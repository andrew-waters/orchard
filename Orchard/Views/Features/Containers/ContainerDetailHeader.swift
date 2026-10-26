import SwiftUI

// MARK: - Container Detail Header
struct ContainerDetailHeader: View {
    let container: Container
    @Binding var selectedTab: TabSelection
    @Binding var selectedCluster: String?
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var clusterService: ClusterService
    @EnvironmentObject var terminalLauncher: TerminalLauncher
    @EnvironmentObject var systemService: SystemService
    @Environment(\.openWindow) private var openWindow
    @State private var showEditConfiguration = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var wasRunningBeforeStop = false
    @State private var showSandboxInfo = false
    @State private var pendingOwnedConfirmation: OwnedSandboxConfirmation?
    @State private var showPluginInfo = false
    @State private var recreateSettings: ClusterRecreateSettings?
    @State private var commitTarget: CommitSheetTarget?

    /// The cluster this container is a node of, for Recreate.
    private var owningCluster: K8sCluster? {
        guard let name = K8sCluster.clusterName(for: container) else { return nil }
        return K8sCluster.group(containers: containerListService.containers).first { $0.name == name }
    }

    /// Badge shown when the container is a sandbox (an isolated workload). Tapping it
    /// explains what that means and shows who manages it and its model endpoint, when it has
    /// either - since a sandbox appears in both the Containers and Sandboxes lists.
    private var sandboxBadge: some View {
        Button(action: { showSandboxInfo.toggle() }) {
            Text("sandbox")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help("Sandbox - an isolated workload")
        .popover(isPresented: $showSandboxInfo) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SwiftUI.Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.accentColor)
                    Text("Sandbox")
                        .font(.headline)
                }
                Text("This container is an isolated workload. It also appears under Compute → Sandboxes.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                if let owner = container.sandboxOwner {
                    Divider()
                    Text("Managed by")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(owner.name) (\(owner.id))")
                        .font(.callout)
                        .textSelection(.enabled)
                }
                if let endpoint = container.sandboxEndpoint {
                    Divider()
                    Text("Model endpoint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(endpoint)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }

    /// Capsule badge shown when the container is not the host's architecture, such as an
    /// amd64 container on Apple silicon, which runs under Rosetta (#147).
    private var platformBadge: some View {
        let platform = container.configuration.platform
        let viaRosetta = ContainerPlatform.needsRosetta(platform.description)
        return Text(viaRosetta ? "\(platform.architecture) · Rosetta" : platform.architecture)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.14)))
            .help(viaRosetta
                ? "Runs as \(platform.description) under Rosetta translation"
                : "Runs as \(platform.description), not this Mac's \(hostContainerPlatform)")
    }

    /// Capsule badge shown when a plugin owns the container (e.g. a k8s cluster node).
    /// Tapping it explains which plugin manages it and what role the container plays.
    private var pluginBadge: some View {
        Button(action: { showPluginInfo.toggle() }) {
            Text(container.pluginBadgeText ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help("Managed by the \(container.owningPlugin ?? "container") plugin")
        .popover(isPresented: $showPluginInfo) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SwiftUI.Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.accentColor)
                    Text("Plugin-managed container")
                        .font(.headline)
                }
                Text("This container is created and managed by the '\(container.owningPlugin ?? "")' container plugin. Its lifecycle is tied to the plugin's resources, so prefer the plugin's commands over acting on it directly.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                if let role = container.pluginRoleDisplay {
                    Divider()
                    Text("Role")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(role)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let cluster = K8sCluster.clusterName(for: container) {
                    Divider()
                    Button("Show in Clusters") {
                        showPluginInfo = false
                        selectedTab = .clusters
                        selectedCluster = cluster
                    }
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }

    private var isRunning: Bool {
        container.status.lowercased() == "running"
    }

    private var isTransitioning: Bool {
        let status = container.status.lowercased()
        return status == "shuttingdown" || status == "shutting-down" ||
               status == "starting" || status == "stopping" ||
               status.contains("transition") || status.contains("pending")
    }

    private var canStart: Bool {
        let status = container.status.lowercased()
        // Only allow starting when truly stopped/created and not transitioning
        return (status == "stopped" || status == "created") && !isTransitioning && !wasRunningBeforeStop
    }

    private var containerName: String {
        container.configuration.id
    }

    private var imageReference: String {
        let reference = container.configuration.image.reference
        let lastComponent = reference.split(separator: "/").last.map(String.init) ?? reference
        return lastComponent.contains(":") ? lastComponent : "\(lastComponent):latest"
    }

    private func startContainer() {
        guard !isStarting else { return }
        isStarting = true
        Task {
            await containerListService.startContainer(container.configuration.id)
            await MainActor.run {
                isStarting = false
            }
        }
    }

    private func stopContainer() {
        guard !isStopping else { return }
        isStopping = true
        Task {
            await containerListService.stopContainer(container.configuration.id)
            await MainActor.run {
                isStopping = false
                wasRunningBeforeStop = true
            }
        }
    }

    /// The warning to fold into Delete's confirmation when another app manages this sandbox.
    private var ownedDeleteWarning: (title: String, message: String)? {
        OwnedSandboxConfirmation.warning(.remove, containers: [container])
    }

    private func exportContainer() {
        ContainerExportFlow.run(containerId: container.configuration.id, service: containerListService)
    }

    private func cleanContainer() {
        Task {
            await containerListService.cleanContainer(container.configuration.id)
        }
    }

    private func deleteContainer() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            await containerListService.removeContainer(container.configuration.id)
            await MainActor.run {
                isDeleting = false
            }
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(containerName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if container.isSandbox {
                        sandboxBadge
                    }
                    if let owner = container.sandboxOwner {
                        Text(owner.badge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.14)))
                            .help("\(owner.name) manages this sandbox")
                    }
                    if container.pluginBadgeText != nil {
                        pluginBadge
                    }
                    if container.configuration.platform.architecture != hostContainerArchitecture {
                        platformBadge
                    }
                }
                Text(imageReference)
                    .font(.subheadline)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                if isRunning {
                    // Container is running - show stop button and terminal options
                    Button("Stop") {
                        OwnedSandboxConfirmation.run(.stop, containers: [container], pending: $pendingOwnedConfirmation) {
                            stopContainer()
                        }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(.orange)
                    .disabled(isStopping)

                    // Terminal buttons - only when running and not stopping
                    if !isStopping {
                        Button("Terminal (sh)") {
                            terminalLauncher.openTerminal(for: container.configuration.id)
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Button("Terminal (bash)") {
                            terminalLauncher.openTerminalWithBash(for: container.configuration.id)
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                } else if let cluster = owningCluster {
                    // A stopped cluster node can't be started, only recreated with its cluster.
                    Button("Recreate Cluster…") {
                        Task { recreateSettings = await clusterService.prepareRecreate(cluster) }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .disabled(clusterService.busyClusters.contains(cluster.name))
                    .help("Apple container can't restart a stopped cluster; this deletes \(cluster.name) and creates it again.")
                } else {
                    // Container is stopped - show start button
                    Button(buttonTitle) {
                        startContainer()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(.green)
                    .disabled(isStarting || isStopping || isDeleting || isTransitioning || !canStart)

                    // Delete button - only when stopped and not starting or transitioning
                    if !isStarting && !isStopping && !isTransitioning {
                        Button("Delete", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(isDeleting)
                    }

                    Button("Edit Configuration") {
                        showEditConfiguration = true
                    }
                    .buttonStyle(BorderedButtonStyle())
                }

                Button("Logs") {
                    openWindow(id: "logs", value: LogTarget.container(container.configuration.id))
                }
                .buttonStyle(BorderedButtonStyle())

                if containerListService.exportingContainers.contains(container.configuration.id) {
                    Button {
                    } label: {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Exporting…")
                        }
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .disabled(true)
                } else {
                    Button("Export…") {
                        exportContainer()
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .help("Save the container's filesystem as a tar archive")
                }

                if supportsContainerCommit(containerVersion: systemService.containerVersion) {
                    if containerListService.committingContainers[container.configuration.id] != nil {
                        Button {
                            commitTarget = CommitSheetTarget(id: container.configuration.id)
                        } label: {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Committing…")
                            }
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .help("Show the commit's progress")
                    } else {
                        Button("Commit…") {
                            commitTarget = CommitSheetTarget(id: container.configuration.id)
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .help("Create an image from the container's filesystem")
                    }
                }

                // Trimming needs a live filesystem to trim, so it's offered only while
                // the container runs.
                if isRunning {
                    if containerListService.cleaningContainers.contains(container.configuration.id) {
                        Button {
                        } label: {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Reclaiming…")
                            }
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(true)
                    } else {
                        Button("Reclaim Space") {
                            cleanContainer()
                        }
                        .buttonStyle(BorderedButtonStyle())
                        .help("Return the container's free disk blocks to the host")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .alert(ownedDeleteWarning?.title ?? "Delete Container?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteContainer()
            }
        } message: {
            Text(ownedDeleteWarning.map { "\($0.message)\n\nThis action cannot be undone." }
                 ?? "Are you sure you want to delete '\(containerName)'? This action cannot be undone.")
        }
        .ownedSandboxConfirmation($pendingOwnedConfirmation)
        .sheet(item: $recreateSettings) { settings in
            CreateClusterView(recreating: settings)
        }
        .sheet(item: $commitTarget) { target in
            CommitContainerView(containerId: target.id)
        }
        .sheet(isPresented: $showEditConfiguration) {
            EditContainerView(container: container)
        }
        .onChange(of: container.status) { oldStatus, newStatus in
            // Clear the "recently stopped" flag when container is truly ready
            let status = newStatus.lowercased()
            let oldStatusLower = oldStatus.lowercased()

            // Only clear the flag if we've truly transitioned from a running/transitioning state to a stable stopped state
            if wasRunningBeforeStop &&
               (status == "stopped" || status == "created") &&
               !isTransitioning &&
               oldStatusLower != status { // Ensure we actually changed states

                // Add a small delay to ensure the container runtime has fully processed the state change
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    wasRunningBeforeStop = false
                }
            }
        }
        .onChange(of: recoveryFailed) { _, failed in
            // Recovery failed for this container - clear our transient state flags.
            if failed {
                wasRunningBeforeStop = false
                isStarting = false
                isStopping = false
                isDeleting = false
            }
        }
    }

    /// Whether this container's automatic recovery failed - persistent state, so the
    /// affordance survives the alert being dismissed or replaced.
    private var recoveryFailed: Bool {
        containerListService.recoveryFailedContainerIDs.contains(container.configuration.id)
    }

    private var buttonTitle: String {
        if isTransitioning {
            return "Transitioning..."
        }

        if wasRunningBeforeStop {
            return "Waiting for shutdown..."
        }

        if recoveryFailed {
            return "Recreate"
        }

        return "Start"
    }
}
