import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
class ContainerService: ObservableObject {
    @Published var containers: [Container] = []
    @Published var isLoading: Bool = false
    @Published var loadingContainers: Set<String> = []
    // Container operation locks to prevent multiple simultaneous operations
    private var containerOperationLocks: Set<String> = []
    private let lockQueue = DispatchQueue(label: "containerOperationLocks", attributes: .concurrent)

    // Container configuration snapshots for recovery
    private var containerSnapshots: [String: Container] = [:]

    // App version info (used for display; updates are handled by Sparkle).
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    /// Runs CLI commands. Injectable so tests can supply a mock.
    private let runner: CommandRunner
    /// The container runtime, behind an app-model-only boundary. Injectable for tests.
    private let backend: ContainerBackend
    /// The app's current user-facing alert. Observed separately by the UI.
    let alertCenter = AlertCenter()
    /// User settings (binary path, preferred terminal).
    let settings: SettingsStore
    /// Opens container shells in the preferred terminal.
    let terminalLauncher: TerminalLauncher
    /// BuildKit builder state and lifecycle.
    let builderService: BuilderService
    /// Container network state and lifecycle.
    let networkService: NetworkService
    /// Image state and operations.
    let imageService: ImageService
    /// Per-container resource stats.
    let statsService: StatsService
    /// DNS domain state and operations.
    let dnsService: DNSService
    /// Container-system state and lifecycle.
    let systemService: SystemService
    private var cancellables = Set<AnyCancellable>()

    init(backend: ContainerBackend = LiveContainerBackend(), runner: CommandRunner = SystemCommandRunner()) {
        self.backend = backend
        self.runner = runner
        let alertCenter = alertCenter
        let settings = SettingsStore(alertCenter: alertCenter)
        self.settings = settings
        self.terminalLauncher = TerminalLauncher(settings: settings, alertCenter: alertCenter)
        let builderService = BuilderService(runner: runner, settings: settings, alertCenter: alertCenter)
        self.builderService = builderService
        let networkService = NetworkService(backend: backend, alertCenter: alertCenter)
        self.networkService = networkService
        let imageService = ImageService(backend: backend, alertCenter: alertCenter)
        self.imageService = imageService
        let statsService = StatsService(backend: backend, alertCenter: alertCenter)
        self.statsService = statsService
        let dnsService = DNSService(runner: runner, settings: settings, alertCenter: alertCenter)
        self.dnsService = dnsService
        let systemService = SystemService(backend: backend, runner: runner, settings: settings, alertCenter: alertCenter)
        self.systemService = systemService

        // Re-publish the extracted stores' changes so views observing this facade
        // still update while the migration is in progress.
        for store in [
            settings.objectWillChange,
            builderService.objectWillChange,
            networkService.objectWillChange,
            imageService.objectWillChange,
            statsService.objectWillChange,
            dnsService.objectWillChange,
            systemService.objectWillChange,
        ] {
            store.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        // Services that read the system-up state for their teardown guard.
        builderService.systemIsRunning = { [weak self] in self?.systemService.systemStatus == .running }
        imageService.systemIsRunning = { [weak self] in self?.systemService.systemStatus == .running }
        statsService.systemIsRunning = { [weak self] in self?.systemService.systemStatus == .running }
        statsService.containersProvider = { [weak self] in self?.containers ?? [] }
        // DNS ↔ System: the default domain is a system property.
        dnsService.refreshSystemProperties = { [weak self] in await self?.systemService.loadSystemProperties(showLoading: false) }
        dnsService.defaultDomain = { [weak self] in
            self?.systemService.systemProperties.first(where: { $0.id == "dns.domain" })?.value
        }
        dnsService.setDefaultDomainProperty = { [weak self] domain in
            self?.systemService.setDNSDomainPropertyOptimistically(domain)
        }
        // System → containers/DNS side effects.
        systemService.onSystemStarted = { [weak self] in await self?.loadContainers() }
        systemService.onSystemStopped = { [weak self] in self?.containers.removeAll() }
        systemService.markDNSDefault = { [weak self] domain in self?.dnsService.markDefault(domain) }
        systemService.reloadDNS = { [weak self] in await self?.dnsService.load(showLoading: false) }
    }

    // MARK: - Settings (forwarded to SettingsStore)

    var customBinaryPath: String? { settings.customBinaryPath }
    var containerBinaryPath: String { settings.containerBinaryPath }
    var isUsingCustomBinary: Bool { settings.isUsingCustomBinary }
    var preferredTerminal: TerminalApp { settings.preferredTerminal }
    var installedTerminals: [TerminalApp] { settings.installedTerminals }

    func setCustomBinaryPath(_ path: String?) { settings.setCustomBinaryPath(path) }
    func resetToDefaultBinary() { settings.resetToDefaultBinary() }
    func validateAndSetCustomBinaryPath(_ path: String?) -> Bool { settings.validateAndSetCustomBinaryPath(path) }
    func setPreferredTerminal(_ terminal: TerminalApp) { settings.setPreferredTerminal(terminal) }

    // Computed property to get all unique mounts from containers
    var allMounts: [ContainerMount] {
        var mountDict: [String: ContainerMount] = [:]

        for container in containers {
            for mount in container.configuration.mounts {
                let mountId = "\(mount.source)->\(mount.destination)"

                if let existingMount = mountDict[mountId] {
                    // Add this container to the existing mount
                    var updatedContainerIds = existingMount.containerIds
                    if !updatedContainerIds.contains(container.configuration.id) {
                        updatedContainerIds.append(container.configuration.id)
                    }
                    mountDict[mountId] = ContainerMount(mount: mount, containerIds: updatedContainerIds)
                } else {
                    // Create new mount entry
                    mountDict[mountId] = ContainerMount(mount: mount, containerIds: [container.configuration.id])
                }
            }
        }

        return Array(mountDict.values).sorted { $0.mount.source < $1.mount.source }
    }

    func loadContainers() async {
        await loadContainers(showLoading: false)
    }

    func loadContainers(showLoading: Bool = true) async {
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

                // Capture configuration snapshots for recovery
                for container in newContainers {
                    self.containerSnapshots[container.configuration.id] = container
                }
            }

            for container in newContainers {
                Log.containers.debug("Container: \(container.configuration.id), Status: \(container.status)")
            }
        } catch {
            await MainActor.run {
                // Only surface while the system is up. When it is stopped or tearing
                // down, the recurring refresh (and NotRunningView's own load) would
                // otherwise flash this error repeatedly over the not-running screen.
                if self.systemService.systemStatus == .running {
                    self.alertCenter.error(error.localizedDescription)
                }
                self.isLoading = false
            }
            Log.containers.error("\(error.localizedDescription)")
        }
    }

    // MARK: - Images (forwarded to ImageService)

    var images: [ContainerImage] { imageService.images }
    var isImagesLoading: Bool { imageService.isImagesLoading }
    var pullProgress: [String: ImagePullProgress] { imageService.pullProgress }
    var isSearching: Bool { imageService.isSearching }
    var searchResults: [RegistrySearchResult] { imageService.searchResults }

    func loadImages() async { await imageService.load() }
    func inspectImage(reference: String) async throws -> ImageInspection { try await imageService.inspect(reference: reference) }
    func pullImage(_ imageName: String) async { await imageService.pull(imageName) }
    func searchImages(_ query: String) async { await imageService.search(query) }
    func clearSearchResults() { imageService.clearSearchResults() }
    func deleteImage(_ imageReference: String) async { await imageService.delete(imageReference) }

    // MARK: - Builders (forwarded to BuilderService)

    var builders: [Builder] { builderService.builders }
    var builderStatus: BuilderStatus { builderService.builderStatus }
    var isBuilderLoading: Bool { builderService.isBuilderLoading }
    var isBuildersLoading: Bool { builderService.isBuildersLoading }

    func loadBuilders() async { await builderService.loadBuilders() }
    func startBuilder() async { await builderService.startBuilder() }
    func stopBuilder() async { await builderService.stopBuilder() }
    func deleteBuilder() async { await builderService.deleteBuilder() }

    // MARK: - Container Stats Management

    // MARK: - Container Stats (forwarded to StatsService)

    var containerStats: [ContainerStats] { statsService.containerStats }
    var isStatsLoading: Bool { statsService.isStatsLoading }

    func loadContainerStats() async { await statsService.load(showLoading: true) }
    func loadContainerStats(showLoading: Bool = true) async { await statsService.load(showLoading: showLoading) }

    // MARK: - System (forwarded to SystemService)

    var systemStatus: SystemStatus { systemService.systemStatus }
    var systemStatusError: String? { systemService.systemStatusError }
    var systemStatusVersionOverride: Bool { systemService.systemStatusVersionOverride }
    var isSystemLoading: Bool { systemService.isSystemLoading }
    var containerVersion: String? { systemService.containerVersion }
    var parsedContainerVersion: String? { systemService.parsedContainerVersion }
    var kernelConfig: KernelConfig { systemService.kernelConfig }
    var isKernelLoading: Bool { systemService.isKernelLoading }
    var systemProperties: [SystemProperty] { systemService.systemProperties }
    var isSystemPropertiesLoading: Bool { systemService.isSystemPropertiesLoading }
    var systemDiskUsage: SystemDiskUsage? { systemService.systemDiskUsage }
    var isSystemDiskUsageLoading: Bool { systemService.isSystemDiskUsageLoading }

    func checkSystemStatus() async { await systemService.checkSystemStatus() }
    func checkSystemStatusIgnoreVersion() async { await systemService.checkSystemStatusIgnoreVersion() }
    func checkContainerVersion() async { await systemService.checkContainerVersion() }
    func startSystem() async { await systemService.startSystem() }
    func stopSystem() async { await systemService.stopSystem() }
    func restartSystem() async { await systemService.restartSystem() }
    func loadKernelConfig() async { await systemService.loadKernelConfig() }
    func setRecommendedKernel() async { await systemService.setRecommendedKernel() }
    func setCustomKernel(binary: String?, tar: String?, arch: KernelArch) async {
        await systemService.setCustomKernel(binary: binary, tar: tar, arch: arch)
    }
    func loadSystemProperties() async { await systemService.loadSystemProperties(showLoading: false) }
    func loadSystemProperties(showLoading: Bool = true) async { await systemService.loadSystemProperties(showLoading: showLoading) }
    func setSystemProperty(_ id: String, value: String) async { await systemService.setSystemProperty(id, value: value) }
    func loadSystemDiskUsage() async { await systemService.loadSystemDiskUsage(showLoading: true) }
    func loadSystemDiskUsage(showLoading: Bool = true) async { await systemService.loadSystemDiskUsage(showLoading: showLoading) }

    private func areContainersEqual(_ old: [Container], _ new: [Container]) -> Bool {
        return old == new
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
                Task {
                    await loadBuilders()
                }
                Task {
                    await refreshUntilContainerStopped(id)
                }
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
                Task {
                    await loadBuilders()
                }
                Task {
                    await refreshUntilContainerStopped(id)
                }
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
        // Check if container operation is already in progress
        let shouldProceed = lockQueue.sync(flags: .barrier) {
            if containerOperationLocks.contains(id) {
                return false
            }
            containerOperationLocks.insert(id)
            return true
        }

        defer {
            let _ = lockQueue.sync(flags: .barrier) {
                containerOperationLocks.remove(id)
            }
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
                }

                Task {
                    await loadBuilders()
                }
                Task {
                    await refreshUntilContainerStarted(id)
                }
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
                            self.alertCenter.error("Container was automatically removed and could not be recovered. Original configuration may be lost.")
                            loadingContainers.remove(id)
                        }

                        Task {
                            await loadContainers()
                        }
                        return
                    }
                } else if isTransitionError {
                    if attempt == maxRetries {
                        await MainActor.run {
                            self.alertCenter.error("Container failed to start after \(maxRetries) attempts. The container may be corrupted.")
                            loadingContainers.remove(id)
                        }

                        Task {
                            await loadContainers()
                        }
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

                    Task {
                        await loadContainers()
                    }
                    return
                }
            }

            // Wait before retrying if needed
            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        // If we get here, all retries failed
        let _ = await MainActor.run {
            loadingContainers.remove(id)
        }
    }

    private func refreshUntilContainerStopped(_ id: String) async {
        var attempts = 0
        let maxAttempts = 10

        while attempts < maxAttempts {
            await loadContainers()

            // Check if container is now stopped
            let shouldStop = await MainActor.run {
                if let container = containers.first(where: { $0.configuration.id == id }) {
                    Log.containers.debug("Checking stop status for \(id): \(container.status)")
                    return container.status.lowercased() != "running"
                } else {
                    Log.containers.debug("Container \(id) not found, assuming stopped")
                    return true  // Container not found, assume it stopped
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
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }

        // Timeout reached, remove loading state
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

            // Check if container is now running
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
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }

        // Timeout reached, remove loading state
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
                Task {
                    await loadBuilders()
                }
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

        // The API returns [containerLog, bootlog] — only read the first (container log)
        guard let containerLog = fileHandles.first else {
            return []
        }

        // Read on a background thread to avoid blocking the main actor
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

    // MARK: - Image Inspection

    // MARK: - DNS Management

    // MARK: - DNS (forwarded to DNSService)

    var dnsDomains: [DNSDomain] { dnsService.dnsDomains }
    var isDNSLoading: Bool { dnsService.isDNSLoading }

    func loadDNSDomains() async { await dnsService.load(showLoading: false) }
    func loadDNSDomains(showLoading: Bool = true) async { await dnsService.load(showLoading: showLoading) }
    @discardableResult
    func createDNSDomain(_ domain: String) async -> Bool { await dnsService.create(domain) }
    func deleteDNSDomain(_ domain: String) async { await dnsService.delete(domain) }
    func setDefaultDNSDomain(_ domain: String) async { await dnsService.setDefault(domain) }

    // MARK: - Networks (forwarded to NetworkService)

    var networks: [ContainerNetwork] { networkService.networks }
    var isNetworksLoading: Bool { networkService.isNetworksLoading }

    func loadNetworks() async { await networkService.load(showLoading: false) }
    func loadNetworks(showLoading: Bool = true) async { await networkService.load(showLoading: showLoading) }
    @discardableResult
    func createNetwork(name: String, subnet: String? = nil, labels: [String] = []) async -> Bool {
        await networkService.create(name: name, subnet: subnet, labels: labels)
    }
    func deleteNetwork(_ networkId: String) async { await networkService.delete(networkId) }


    // MARK: - Container Terminal (forwarded to TerminalLauncher)

    func openTerminal(for containerId: String, shell: String = "sh") {
        terminalLauncher.openTerminal(for: containerId, shell: shell)
    }

    func openTerminalWithBash(for containerId: String) {
        terminalLauncher.openTerminalWithBash(for: containerId)
    }

    // MARK: - Container Run Management

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

    // MARK: - Container Recovery

    private func recoverContainer(_ id: String) async -> Bool {
        guard let snapshot = await MainActor.run(body: { containerSnapshots[id] }) else {
            Log.containers.debug("No snapshot available for container \(id)")
            return false
        }

        Log.containers.debug("Attempting to recover container \(id) from snapshot...")

        let config = snapshot.configuration

        // Build a ContainerRunConfig from the snapshot for recovery
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
                containerPath: mount.destination
            ))
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

            // Build environment strings
            var envStrings: [String] = []
            for envVar in config.environmentVariables {
                if !envVar.key.isEmpty {
                    envStrings.append("\(envVar.key)=\(envVar.value)")
                }
            }

            // Build volumes
            var volumes: [ContainerCreateSpec.Volume] = []
            for vol in config.volumeMappings {
                if !vol.hostPath.isEmpty && !vol.containerPath.isEmpty {
                    volumes.append(.init(hostPath: vol.hostPath, containerPath: vol.containerPath, readonly: vol.readonly))
                }
            }

            // Build published ports
            var ports: [ContainerCreateSpec.Port] = []
            for pm in config.portMappings {
                if let hp = UInt16(pm.hostPort), let cp = UInt16(pm.containerPort) {
                    ports.append(.init(hostPort: hp, containerPort: cp, transportProtocol: pm.transportProtocol))
                }
            }

            // Build command override
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

            await MainActor.run {
                Task {
                    await loadContainers()
                }
            }
            return true
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to run container: \(error.localizedDescription)")
            }
            return false
        }
    }

}

