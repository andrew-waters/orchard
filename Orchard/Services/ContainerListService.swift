import Foundation
import SwiftUI

/// Owns the container list and lifecycle: load, start (with retry/recovery), stop, kill,
/// remove, run, recreate, logs, and the mounts derived from the list.
@MainActor
final class ContainerListService: ObservableObject {
    @Published var containers: [Container] = [] {
        didSet { allMounts = Self.computeMounts(containers) }
    }
    /// Unique mounts across the current containers. Recomputed only when `containers`
    /// changes, not on every read — several views read it on each objectWillChange tick.
    @Published private(set) var allMounts: [ContainerMount] = []
    @Published var loadingContainers: Set<String> = []
    @Published var isLoading: Bool = false
    /// Containers whose automatic recovery failed — drives the persistent "Recreate"
    /// affordance, which must outlive the transient alert. Cleared on a successful start.
    @Published var recoveryFailedContainerIDs: Set<String> = []

    private let backend: ContainerBackend
    private let alertCenter: AlertCenter

    /// Refresh builder state after a lifecycle change. Set by the owner.
    var reloadBuilders: () async -> Void = {}

    /// Delay between polls in the `refreshUntilContainer…` loops. Injected; production uses
    /// the 0.5s default, tests pass 0 to drive the loops without real sleeps.
    private let pollInterval: TimeInterval
    /// Number of polls before a refresh loop gives up and clears the loading state.
    let maxRefreshAttempts = 10

    // Prevent multiple simultaneous operations on the same container.
    private var containerOperationLocks: Set<String> = []
    private let lockQueue = DispatchQueue(label: "containerOperationLocks", attributes: .concurrent)
    // Configuration snapshots for recovery.
    private var containerSnapshots: [String: Container] = [:]

    init(backend: ContainerBackend, alertCenter: AlertCenter, pollInterval: TimeInterval = 0.5) {
        self.backend = backend
        self.alertCenter = alertCenter
        self.pollInterval = pollInterval
    }

    private static func computeMounts(_ containers: [Container]) -> [ContainerMount] {
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
            isLoading = true
            self.alertCenter.dismiss()
        }

        do {
            let newContainers = try await backend.listContainers()

            if !areContainersEqual(self.containers, newContainers) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.containers = newContainers
                }
            }
            self.isLoading = false
            for container in newContainers {
                self.containerSnapshots[container.configuration.id] = container
            }

            for container in newContainers {
                Log.containers.debug("Container: \(container.configuration.id), Status: \(container.status)")
            }
        } catch {
            // Background refreshes stay silent; only a user-initiated load alerts.
            self.alertCenter.error(error.localizedDescription, source: showLoading ? .user : .background)
            self.isLoading = false
            Log.containers.error("\(error.localizedDescription)")
        }
    }

    func forceStopContainer(_ id: String) async {
        loadingContainers.insert(id)
        self.alertCenter.dismiss()

        do {
            try await backend.killContainer(id: id, signal: 9)
            Log.containers.debug("Container \(id) force stop (SIGKILL) sent")
            Task { await self.reloadBuilders() }
            Task { await self.refreshUntilContainerStopped(id) }
        } catch {
            loadingContainers.remove(id)
            self.alertCenter.error("Failed to force stop container: \(error.localizedDescription)")
            Log.containers.error("Error force stopping container: \(error.localizedDescription)")
        }
    }

    func stopContainer(_ id: String) async {
        loadingContainers.insert(id)
        self.alertCenter.dismiss()

        do {
            try await backend.stopContainer(id: id)
            Log.containers.debug("Container \(id) stop command sent successfully")
            Task { await self.reloadBuilders() }
            Task { await self.refreshUntilContainerStopped(id) }
        } catch {
            loadingContainers.remove(id)
            self.alertCenter.error("Failed to stop container: \(error.localizedDescription)")
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
        loadingContainers.insert(id)
        self.alertCenter.dismiss()

        for attempt in 1...maxRetries {
            do {
                try await backend.bootstrapAndStart(id: id)

                Log.containers.debug("Container \(id) start command sent successfully (attempt \(attempt))")
                self.recoveryFailedContainerIDs.remove(id)

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
                        // recoverContainer → runContainer → createContainer already bootstraps
                        // and starts the container, so this is a completed start — do NOT loop
                        // back into another bootstrapAndStart on the now-running container.
                        Log.containers.debug("Container \(id) successfully recovered and started")
                        self.recoveryFailedContainerIDs.remove(id)
                        Task { await self.reloadBuilders() }
                        Task { await self.refreshUntilContainerStarted(id) }
                        return
                    } else {
                        Log.containers.error("Container \(id) recovery failed")
                        self.recoveryFailedContainerIDs.insert(id)
                        self.alertCenter.error("Container was automatically removed and could not be recovered. Original configuration may be lost.")
                        loadingContainers.remove(id)
                        Task { await self.loadContainers() }
                        return
                    }
                } else if isTransitionError {
                    if attempt == maxRetries {
                        self.alertCenter.error("Container failed to start after \(maxRetries) attempts. The container may be corrupted.")
                        loadingContainers.remove(id)
                        Task { await self.loadContainers() }
                        return
                    } else {
                        self.alertCenter.error("Container is in transition state, retrying...")
                    }
                } else {
                    self.alertCenter.error("Failed to start container: \(errorMsg)")
                    loadingContainers.remove(id)
                    Task { await self.loadContainers() }
                    return
                }
            }

            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        loadingContainers.remove(id)
    }

    private func refreshUntilContainerStopped(_ id: String) async {
        var attempts = 0

        while attempts < maxRefreshAttempts {
            await loadContainers()

            let shouldStop: Bool
            if let container = containers.first(where: { $0.configuration.id == id }) {
                Log.containers.debug("Checking stop status for \(id): \(container.status)")
                shouldStop = container.status.lowercased() != "running"
            } else {
                Log.containers.debug("Container \(id) not found, assuming stopped")
                shouldStop = true
            }

            if shouldStop {
                Log.containers.debug("Container \(id) has stopped, removing loading state")
                loadingContainers.remove(id)
                return
            }

            attempts += 1
            Log.containers.debug("Container \(id) still running, attempt \(attempts)/\(self.maxRefreshAttempts)")
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        Log.containers.debug("Timeout reached for container \(id), removing loading state")
        loadingContainers.remove(id)
    }

    private func refreshUntilContainerStarted(_ id: String) async {
        var attempts = 0

        while attempts < maxRefreshAttempts {
            await loadContainers()

            let isRunning: Bool
            if let container = containers.first(where: { $0.configuration.id == id }) {
                Log.containers.debug("Checking start status for \(id): \(container.status)")
                isRunning = container.status.lowercased() == "running"
            } else {
                isRunning = false
            }

            if isRunning {
                Log.containers.debug("Container \(id) has started, removing loading state")
                loadingContainers.remove(id)
                return
            }

            attempts += 1
            Log.containers.debug("Container \(id) not running yet, attempt \(attempts)/\(self.maxRefreshAttempts)")
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        Log.containers.debug("Timeout reached for container \(id), removing loading state")
        loadingContainers.remove(id)
    }

    func removeContainer(_ id: String) async {
        loadingContainers.insert(id)
        self.alertCenter.dismiss()

        do {
            try await backend.deleteContainer(id: id, force: false)
            Log.containers.debug("Container \(id) remove command sent successfully")
            Task { await self.reloadBuilders() }
            self.containers.removeAll { $0.configuration.id == id }
            loadingContainers.remove(id)
        } catch {
            loadingContainers.remove(id)
            self.alertCenter.error("Failed to remove container: \(error.localizedDescription)")
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
            self.alertCenter.error("Failed to recreate container: \(error.localizedDescription)")
        }
    }

    // Recovery recreates an auto-removed container from its snapshot. It preserves every
    // field the create path (ContainerRunConfig → ContainerCreateSpec → createContainer)
    // supports: env, ports, volumes (incl. readonly), working directory, network, DNS.
    // Labels, resources (cpus/memory), and hostname are NOT preserved — no field exists for
    // them anywhere in the create path (a normal `run` drops them too); adding them means
    // extending the spec and the XPC create call. Command override is intentionally not
    // reconstructed: the snapshot stores the fully-resolved argv (image entrypoint already
    // applied), so re-feeding it as an override would double-apply the entrypoint.
    private func recoverContainer(_ id: String) async -> Bool {
        guard let snapshot = containerSnapshots[id] else {
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
            volumeMappings.append(.init(
                hostPath: mount.source,
                containerPath: mount.destination,
                readonly: mount.options.contains("ro")
            ))
        }

        let runConfig = ContainerRunConfig(
            name: id,
            image: config.image.reference,
            detached: true,
            environmentVariables: envVars,
            portMappings: portMappings,
            volumeMappings: volumeMappings,
            workingDirectory: config.initProcess.workingDirectory,
            dnsDomain: config.dns.domain ?? "",
            network: snapshot.networks.first?.network ?? ""
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
            self.alertCenter.error("Failed to run container: \(error.localizedDescription)")
            return false
        }
    }

    func deleteMounts(_ mounts: [ContainerMount]) async {
        var deletedCount = 0
        var failedCount = 0
        for mount in mounts {
            for containerId in mount.containerIds {
                guard let container = containers.first(where: { $0.configuration.id == containerId }) else { continue }
                
                let oldConfig = container.configuration
                let updatedMounts = oldConfig.mounts.filter { m in
                    !(m.source == mount.mount.source && m.destination == mount.mount.destination)
                }
                
                var envVars: [ContainerRunConfig.EnvironmentVariable] = []
                for env in oldConfig.initProcess.environment {
                    let parts = env.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        envVars.append(.init(key: String(parts[0]), value: String(parts[1])))
                    }
                }
                
                var portMappings: [ContainerRunConfig.PortMapping] = []
                for port in oldConfig.publishedPorts {
                    portMappings.append(.init(
                        hostPort: "\(port.hostPort)",
                        containerPort: "\(port.containerPort)",
                        transportProtocol: port.transportProtocol
                    ))
                }
                
                var volumeMappings: [ContainerRunConfig.VolumeMapping] = []
                for m in updatedMounts {
                    let isReadonly = m.options.contains("ro")
                    volumeMappings.append(.init(
                        hostPath: m.source,
                        containerPath: m.destination,
                        readonly: isReadonly
                    ))
                }
                
                let runConfig = ContainerRunConfig(
                    name: oldConfig.id,
                    image: oldConfig.image.reference,
                    detached: true,
                    removeAfterStop: false,
                    environmentVariables: envVars,
                    portMappings: portMappings,
                    volumeMappings: volumeMappings,
                    workingDirectory: oldConfig.initProcess.workingDirectory,
                    commandOverride: oldConfig.initProcess.arguments.joined(separator: " "),
                    dnsDomain: oldConfig.dns.domain ?? "",
                    network: container.networks.first?.network ?? ""
                )
                
                do {
                    try await backend.deleteContainer(id: containerId, force: true)
                    let started = await runContainer(config: runConfig)
                    if started {
                        deletedCount += 1
                    } else {
                        failedCount += 1
                    }
                } catch {
                    failedCount += 1
                }
            }
        }
        await loadContainers(showLoading: false)
        if failedCount > 0 {
            alertCenter.error("Failed to remove mount(s) from \(failedCount) container(s)")
        }
    }

}
