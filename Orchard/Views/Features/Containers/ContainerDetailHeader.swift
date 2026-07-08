import SwiftUI

// MARK: - Container Detail Header
struct ContainerDetailHeader: View {
    let container: Container
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var terminalLauncher: TerminalLauncher
    @Environment(\.openWindow) private var openWindow
    @State private var showEditConfiguration = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var wasRunningBeforeStop = false
    @State private var showSandboxInfo = false

    /// Shield badge shown when the container is a sandbox (wired to a local model). Tapping
    /// it explains what that means and shows the endpoint - since a sandbox appears in both
    /// the Containers and Local AI → Sandboxes lists.
    private var sandboxBadge: some View {
        Button(action: { showSandboxInfo.toggle() }) {
            SwiftUI.Image(systemName: "shield.lefthalf.filled")
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .help("Sandbox - wired to a local model")
        .popover(isPresented: $showSandboxInfo) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SwiftUI.Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.accentColor)
                    Text("Sandbox")
                        .font(.headline)
                }
                Text("This container is wired to a local model. It also appears in Local AI → Sandboxes.")
                    .font(.callout)
                    .foregroundColor(.secondary)
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
                        stopContainer()
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .alert("Delete Container?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteContainer()
            }
        } message: {
            Text("Are you sure you want to delete '\(containerName)'? This action cannot be undone.")
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
