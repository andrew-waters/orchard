import Foundation
import SwiftUI

/// Owns the container list and lifecycle: load, start (with retry/recovery), stop, kill,
/// remove, run, recreate, logs, and the mounts derived from the list.
@MainActor
final class ContainerListService: ObservableObject {
    @Published var containers: [Container] = []
    @Published var loadingContainers: Set<String> = []
    @Published var isLoading: Bool = false
    /// Containers whose automatic recovery failed — drives the persistent "Recreate"
    /// affordance, which must outlive the transient alert. Cleared on a successful start.
    @Published var recoveryFailedContainerIDs: Set<String> = []

    private let backend: ContainerBackend
    private let alertCenter: AlertCenter

    /// Refresh builder state after a lifecycle change. Set by the owner.
    var reloadBuilders: () async -> Void = {}

    // Prevent multiple simultaneous operations on the same container.
    private var containerOperationLocks: Set<String> = []
    private let lockQueue = DispatchQueue(label: "containerOperationLocks", attributes: .concurrent)
    // Configuration snapshots for recovery.
    private var containerSnapshots: [String: Container] = [:]

    init(backend: ContainerBackend, alertCenter: AlertCenter) {
        self.backend = backend
        self.alertCenter = alertCenter
    }

    /// All unique mounts across the current containers.
    var allMounts: [ContainerMount] {
        var mountDict: [String: ContainerMount] = [:]
        for container in containers {
            for mount in container.configuration.mounts {
                let mountId = "\(mount.source)->\(mount.destination)"
                if let existingMount = mountDict[mountId] {
                    var updatedContainerIds = existingMount.containerIds
                    if !updatedContainerIds.contains(container.configuration.id) {
                        updatedContainerIds.append(container.configuration.id)
                    }
                    mountDict[mountId] = ContainerMount(mount: mount, containerIds: updatedContainerIds)
                } else {
                    mountDict[mountId] = ContainerMount(mount: mount, containerIds: [container.configuration.id])
                }
            }
        }
        return Array(mountDict.values).sorted { $0.mount.source < $1.mount.source }
    }

    private func areContainersEqual(_ old: [Container], _ new: [Container]) -> Bool {
        old == new
    }

    func loadContainers(showLoading: Bool = false) async {
        if showLoading {
            await MainActor.run {
                isLoading = true
                self.alertCenter.dismiss()
            }
        }

        do {
            let newContainers = try await backend.listContainers()

            await MainActor.run {
                if !areContainersEqual(self.containers, newContainers) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.containers = newContainers
                    }
                }
                self.isLoading = false
                for container in newContainers {
                    self.containerSnapshots[container.configuration.id] = container
                }
            }

            for container in newContainers {
                Log.containers.debug("Container: \(container.configuration.id), Status: \(container.status)")
            }
        } catch {
            await MainActor.run {
                // Background refreshes stay silent; only a user-initiated load alerts.
                self.alertCenter.error(error.localizedDescription, source: showLoading ? .user : .background)
                self.isLoading = false
            }
            Log.containers.error("\(error.localizedDescription)")
        }
    }

    func forceStopContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            self.alertCenter.dismiss()
        }

        do {
            try await backend.killContainer(id: id, signal: 9)
            await MainActor.run {
                Log.containers.debug("Container \(id) force stop (SIGKILL) sent")
                Task { await self.reloadBuilders() }
                Task { await self.refreshUntilContainerStopped(id) }
            }
        } catch {
            await MainActor.run {
                loadingContainers.remove(id)
                self.alertCenter.error("Failed to force stop container: \(error.localizedDescription)")
            }
            Log.containers.error("Error force stopping container: \(error.localizedDescription)")
        }
    }

    func stopContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            self.alertCenter.dismiss()
        }

        do {
            try await backend.stopContainer(id: id)
            await MainActor.run {
                Log.containers.debug("Container \(id) stop command sent successfully")
                Task { await self.reloadBuilders() }
                Task { await self.refreshUntilContainerStopped(id) }
            }
        } catch {
            await MainActor.run {
                loadingContainers.remove(id)
                self.alertCenter.error("Failed to stop container: \(error.localizedDescription)")
            }
            Log.containers.error("Error stopping container: \(error.localizedDescription)")
        }
    }

    func startContainer(_ id: String, maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) async {
        let shouldProceed = lockQueue.sync(flags: .barrier) {
            if containerOperationLocks.contains(id) { return false }
            containerOperationLocks.insert(id)
            return true
        }

        defer {
            _ = lockQueue.sync(flags: .barrier) { containerOperationLocks.remove(id) }
        }

        guard shouldProceed else {
            Log.containers.debug("DEBUG: Container \(id) operation already in progress, ignoring duplicate call")
            return
        }

        await startContainerWithRetry(id, maxRetries: maxRetries, retryDelay: retryDelay)
    }

    private func startContainerWithRetry(_ id: String, maxRetries: Int, retryDelay: TimeInterval) async {
        await MainActor.run {
            loadingContainers.insert(id)
            self.alertCenter.dismiss()
        }

        for attempt in 1...maxRetries {
            do {
                try await backend.bootstrapAndStart(id: id)

                await MainActor.run {
                    Log.containers.debug("Container \(id) start command sent successfully (attempt \(attempt))")
                    self.recoveryFailedContainerIDs.remove(id)
                }

                Task { await self.reloadBuilders() }
                Task { await self.refreshUntilContainerStarted(id) }
                return
            } catch {
                let errorMsg = error.localizedDescription
                Log.containers.error("Container \(id) failed to start (attempt \(attempt)): \(errorMsg)")

                let classified = OrchardError.classifyStartError(error, id: id)
                let containerNotFound = classified == .containerNotFound(id: id)
                let isTransitionError = classified == .containerInTransition(id: id)

                if containerNotFound {
                    Log.containers.debug("Container \(id) was auto-removed by runtime, attempting automatic recovery...")

                    if await recoverContainer(id) {
                        Log.containers.debug("Container \(id) successfully recovered, retrying start...")
                        continue
                    } else {
                        await MainActor.run {
                            Log.containers.error("Container \(id) recovery failed")
                            self.recoveryFailedContainerIDs.insert(id)
                            self.alertCenter.error("Container was automatically removed and could not be recovered. Original configuration may be lost.")
                            loadingContainers.remove(id)
                        }
                        Task { await self.loadContainers() }
                        return
                    }
                } else if isTransitionError {
                    if attempt == maxRetries {
                        await MainActor.run {
                            self.alertCenter.error("Container failed to start after \(maxRetries) attempts. The container may be corrupted.")
                            loadingContainers.remove(id)
                        }
                        Task { await self.loadContainers() }
                        return
                    } else {
                        await MainActor.run {
                            self.alertCenter.error("Container is in transition state, retrying...")
                        }
                    }
                } else {
                    await MainActor.run {
                        self.alertCenter.error("Failed to start container: \(errorMsg)")
                        loadingContainers.remove(id)
                    }
                    Task { await self.loadContainers() }
                    return
                }
            }

            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        _ = await MainActor.run { loadingContainers.remove(id) }
    }

    private func refreshUntilContainerStopped(_ id: String) async {
        var attempts = 0
        let maxAttempts = 10

        while attempts < maxAttempts {
            await loadContainers()

            let shouldStop = await MainActor.run {
                if let container = containers.first(where: { $0.configuration.id == id }) {
                    Log.containers.debug("Checking stop status for \(id): \(container.status)")
                    return container.status.lowercased() != "running"
                } else {
                    Log.containers.debug("Container \(id) not found, assuming stopped")
                    return true
                }
            }

            if shouldStop {
                await MainActor.run {
                    Log.containers.debug("Container \(id) has stopped, removing loading state")
                    loadingContainers.remove(id)
                }
                return
            }

            attempts += 1
            Log.containers.debug("Container \(id) still running, attempt \(attempts)/\(maxAttempts)")
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        await MainActor.run {
            Log.containers.debug("Timeout reached for container \(id), removing loading state")
            loadingContainers.remove(id)
        }
    }

    private func refreshUntilContainerStarted(_ id: String) async {
        var attempts = 0
        let maxAttempts = 10

        while attempts < maxAttempts {
            await loadContainers()

            let isRunning = await MainActor.run {
                if let container = containers.first(where: { $0.configuration.id == id }) {
                    Log.containers.debug("Checking start status for \(id): \(container.status)")
                    return container.status.lowercased() == "running"
                }
                return false
            }

            if isRunning {
                await MainActor.run {
                    Log.containers.debug("Container \(id) has started, removing loading state")
                    loadingContainers.remove(id)
                }
                return
            }

            attempts += 1
            Log.containers.debug("Container \(id) not running yet, attempt \(attempts)/\(maxAttempts)")
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        await MainActor.run {
            Log.containers.debug("Timeout reached for container \(id), removing loading state")
            loadingContainers.remove(id)
        }
    }

    func removeContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            self.alertCenter.dismiss()
        }

        do {
            try await backend.deleteContainer(id: id, force: false)
            await MainActor.run {
                Log.containers.debug("Container \(id) remove command sent successfully")
                Task { await self.reloadBuilders() }
                self.containers.removeAll { $0.configuration.id == id }
                loadingContainers.remove(id)
            }
        } catch {
            await MainActor.run {
                loadingContainers.remove(id)
                self.alertCenter.error("Failed to remove container: \(error.localizedDescription)")
            }
            Log.containers.error("Error removing container: \(error.localizedDescription)")
        }
    }

    func removeContainers(_ ids: [String]) async {
        for id in ids {
            await removeContainer(id)
        }
    }

    func fetchContainerLogs(containerId: String, tailLines: Int = 5000) async throws -> [String] {
        let fileHandles = try await backend.containerLogs(id: containerId)

        // The API returns [containerLog, bootlog] — only read the first (container log).
        guard let containerLog = fileHandles.first else {
            return []
        }

        return try await Task.detached {
            let data = containerLog.readDataToEndOfFile()
            guard let fullText = String(data: data, encoding: .utf8) else {
                return [String]()
            }
            let lines = fullText.components(separatedBy: "\n")
            if lines.count > tailLines {
                return Array(lines.suffix(tailLines))
            }
            return lines
        }.value
    }

    func recreateContainer(oldContainerId: String, newConfig: ContainerRunConfig) async {
        do {
            try await backend.deleteContainer(id: oldContainerId, force: true)
            await runContainer(config: newConfig)
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to recreate container: \(error.localizedDescription)")
            }
        }
    }

    private func recoverContainer(_ id: String) async -> Bool {
        guard let snapshot = await MainActor.run(body: { containerSnapshots[id] }) else {
            Log.containers.debug("No snapshot available for container \(id)")
            return false
        }

        Log.containers.debug("Attempting to recover container \(id) from snapshot...")

        let config = snapshot.configuration

        var envVars: [ContainerRunConfig.EnvironmentVariable] = []
        for env in config.initProcess.environment {
            let parts = env.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                envVars.append(.init(key: String(parts[0]), value: String(parts[1])))
            }
        }

        var portMappings: [ContainerRunConfig.PortMapping] = []
        for port in config.publishedPorts {
            portMappings.append(.init(
                hostPort: "\(port.hostPort)",
                containerPort: "\(port.containerPort)",
                transportProtocol: port.transportProtocol
            ))
        }

        var volumeMappings: [ContainerRunConfig.VolumeMapping] = []
        for mount in config.mounts {
            volumeMappings.append(.init(hostPath: mount.source, containerPath: mount.destination))
        }

        let runConfig = ContainerRunConfig(
            name: id,
            image: config.image.reference,
            detached: true,
            environmentVariables: envVars,
            portMappings: portMappings,
            volumeMappings: volumeMappings,
            dnsDomain: config.dns.domain ?? ""
        )

        let started = await runContainer(config: runConfig)
        if started {
            Log.containers.debug("Container \(id) recovered successfully")
            return true
        } else {
            Log.containers.error("Container recovery failed")
            return false
        }
    }

    @discardableResult
    func runContainer(config: ContainerRunConfig) async -> Bool {
        do {
            let id = config.name.isEmpty ? UUID().uuidString.lowercased().prefix(12).description : config.name

            var envStrings: [String] = []
            for envVar in config.environmentVariables where !envVar.key.isEmpty {
                envStrings.append("\(envVar.key)=\(envVar.value)")
            }

            var volumes: [ContainerCreateSpec.Volume] = []
            for vol in config.volumeMappings where !vol.hostPath.isEmpty && !vol.containerPath.isEmpty {
                volumes.append(.init(hostPath: vol.hostPath, containerPath: vol.containerPath, readonly: vol.readonly))
            }

            var ports: [ContainerCreateSpec.Port] = []
            for pm in config.portMappings {
                if let hp = UInt16(pm.hostPort), let cp = UInt16(pm.containerPort) {
                    ports.append(.init(hostPort: hp, containerPort: cp, transportProtocol: pm.transportProtocol))
                }
            }

            var commandArgs: [String] = []
            if !config.commandOverride.isEmpty {
                commandArgs = config.commandOverride.split(separator: " ").map(String.init)
            }

            let spec = ContainerCreateSpec(
                id: id,
                imageRef: config.image,
                environment: envStrings,
                workingDirectory: config.workingDirectory,
                commandOverride: commandArgs,
                volumes: volumes,
                publishedPorts: ports,
                dnsDomain: config.dnsDomain,
                networkName: config.network,
                autoRemove: config.removeAfterStop
            )
            try await backend.createContainer(spec)

            recoveryFailedContainerIDs.remove(id)
            Task { await self.loadContainers() }
            return true
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to run container: \(error.localizedDescription)")
            }
            return false
        }
    }
}
