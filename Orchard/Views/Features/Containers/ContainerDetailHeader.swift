import SwiftUI

// MARK: - Container Detail Header
struct ContainerDetailHeader: View {
    let container: Container
    @EnvironmentObject var containerService: ContainerService
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var wasRunningBeforeStop = false

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

    private func startContainer() {
        guard !isStarting else { return }
        isStarting = true
        Task {
            await containerService.startContainer(container.configuration.id)
            await MainActor.run {
                isStarting = false
            }
        }
    }

    private func stopContainer() {
        guard !isStopping else { return }
        isStopping = true
        Task {
            await containerService.stopContainer(container.configuration.id)
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
            await containerService.removeContainer(container.configuration.id)
            await MainActor.run {
                isDeleting = false
            }
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(containerName)
                    .font(.title2)
                    .fontWeight(.semibold)
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
                            containerService.openTerminal(for: container.configuration.id)
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Button("Terminal (bash)") {
                            containerService.openTerminalWithBash(for: container.configuration.id)
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
                }
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
        .onChange(of: containerService.errorMessage) { _, errorMessage in
            // If container recovery failed, clear our state flags
            if let error = errorMessage, error.contains("could not be recovered") {
                wasRunningBeforeStop = false
                isStarting = false
                isStopping = false
                isDeleting = false
            }
        }
    }

    private var buttonTitle: String {
        if isTransitioning {
            return "Transitioning..."
        }

        if wasRunningBeforeStop {
            return "Waiting for shutdown..."
        }

        // Check if there's a recovery failure error message
        if let error = containerService.errorMessage, error.contains("could not be recovered") {
            return "Recreate"
        }

        return "Start"
    }
}
