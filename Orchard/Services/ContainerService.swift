import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
class ContainerService: ObservableObject {
    @Published var containers: [Container] = []
    @Published var images: [ContainerImage] = []
    @Published var isLoading: Bool = false
    @Published var isImagesLoading: Bool = false
    @Published var systemStatus: SystemStatus = .unknown
    @Published var systemStatusError: String?
    @Published var systemStatusVersionOverride: Bool = false
    @Published var isSystemLoading = false
    @Published var loadingContainers: Set<String> = []
    @Published var containerVersion: String?
    @Published var parsedContainerVersion: String?
    @Published var dnsDomains: [DNSDomain] = []
    @Published var isDNSLoading = false
    @Published var kernelConfig: KernelConfig = KernelConfig()
    @Published var isKernelLoading = false
    @Published var containerStats: [ContainerStats] = []
    @Published var isStatsLoading: Bool = false
    @Published var systemDiskUsage: SystemDiskUsage? = nil
    @Published var isSystemDiskUsageLoading: Bool = false
    @Published var pullProgress: [String: ImagePullProgress] = [:]
    @Published var isSearching: Bool = false
    @Published var searchResults: [RegistrySearchResult] = []
    @Published var systemProperties: [SystemProperty] = []
    @Published var isSystemPropertiesLoading = false
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

        // Re-publish the extracted stores' changes so views observing this facade
        // still update while the migration is in progress.
        for store in [settings.objectWillChange, builderService.objectWillChange, networkService.objectWillChange] {
            store.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        // BuilderService needs to know whether the system is up (teardown guard).
        builderService.systemIsRunning = { [weak self] in self?.systemStatus == .running }
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

    enum SystemStatus {
        case unknown
        case stopped
        case running
        case newerVersion
        case unsupportedVersion

        var color: Color {
            switch self {
            case .unknown, .stopped:
                return .gray
            case .running:
                return .green
            case .newerVersion:
                return .yellow
            case .unsupportedVersion:
                return .red
            }
        }

        var text: String {
            switch self {
            case .unknown:
                return "unknown"
            case .stopped:
                return "stopped"
            case .running:
                return "running"
            case .newerVersion:
                return "version not yet supported"
            case .unsupportedVersion:
                return "unsupported version"
            }
        }
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
                if self.systemStatus == .running {
                    self.alertCenter.error(error.localizedDescription)
                }
                self.isLoading = false
            }
            Log.containers.error("\(error.localizedDescription)")
        }
    }

    func loadImages() async {
        await MainActor.run {
            isImagesLoading = true
            self.alertCenter.dismiss()
        }

        do {
            let newImages = try await backend.listImages()

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.images = newImages
                }
                self.isImagesLoading = false
            }

            for image in newImages {
                Log.containers.debug("Image: \(image.reference)")
            }
        } catch {
            await MainActor.run {
                if self.systemStatus == .running {
                    self.alertCenter.error(error.localizedDescription)
                }
                self.isImagesLoading = false
            }
            Log.containers.error("\(error.localizedDescription)")
        }
    }

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

    func loadContainerStats() async {
        await loadContainerStats(showLoading: true)
    }

    func loadContainerStats(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isStatsLoading = true
                self.alertCenter.dismiss()
            }
        }

        let runningContainers = containers.filter { $0.status == "running" }

        var allStats: [Orchard.ContainerStats] = []
        var failedContainers: [String] = []
        for container in runningContainers {
            do {
                let stats = try await backend.stats(id: container.configuration.id)
                allStats.append(stats)
            } catch {
                failedContainers.append(container.configuration.id)
                Log.containers.error("Failed to load stats for container \(container.configuration.id): \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            self.containerStats = allStats
            self.isStatsLoading = false
            // Only surface an error if every running container failed — a single broken
            // container should not blank out the whole stats page — and only while the
            // system is up, so a stop/shutdown teardown doesn't surface a spurious error.
            if self.systemStatus == .running
                && !runningContainers.isEmpty
                && failedContainers.count == runningContainers.count {
                self.alertCenter.error("Unable to read container stats. Check that the container service is running.")
            }
        }
    }

    // MARK: - System Disk Usage Management

    func loadSystemDiskUsage() async {
        await loadSystemDiskUsage(showLoading: true)
    }

    func loadSystemDiskUsage(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isSystemDiskUsageLoading = true
            }
        }

        do {
            let diskUsage = try await backend.diskUsage()

            await MainActor.run {
                self.systemDiskUsage = diskUsage
                self.isSystemDiskUsageLoading = false
            }
        } catch {
            await MainActor.run {
                self.systemDiskUsage = nil
                self.isSystemDiskUsageLoading = false
                if self.systemStatus == .running {
                    self.alertCenter.error("Failed to load system disk usage: \(error.localizedDescription)")
                }
            }
        }
    }

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

    func checkSystemStatus() async {
        do {
            let health = try await backend.ping()

            await MainActor.run {
                self.containerVersion = health.apiServerVersion
                self.parsedContainerVersion = health.apiServerVersion
                self.systemStatus = .running
                self.systemStatusError = nil
            }
        } catch {
            let detail = "\(type(of: error)): \(String(describing: error))"
            await MainActor.run {
                self.containerVersion = nil
                self.parsedContainerVersion = nil
                self.systemStatus = .stopped
                self.systemStatusError = detail
            }
        }
    }

    func checkSystemStatusIgnoreVersion() async {
        self.systemStatusVersionOverride = true
        await checkSystemStatus()
    }

    func checkContainerVersion() async {
        await checkSystemStatus()
    }

    func startSystem() async {
        await MainActor.run {
            isSystemLoading = true
            self.alertCenter.dismiss()
        }

        do {
            _ = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "start"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .running
            }

            Log.containers.debug("Container system started successfully")
            await loadContainers()

        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to start system: \(error.localizedDescription)")
                self.isSystemLoading = false
            }
            Log.containers.error("Error starting system: \(error.localizedDescription)")
        }
    }

    func stopSystem() async {
        await MainActor.run {
            isSystemLoading = true
            self.alertCenter.dismiss()
        }

        do {
            _ = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "stop"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .stopped
                self.containers.removeAll()
            }

            Log.containers.debug("Container system stopped successfully")

        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to stop system: \(error.localizedDescription)")
                self.isSystemLoading = false
            }
            Log.containers.error("Error stopping system: \(error.localizedDescription)")
        }
    }

    func restartSystem() async {
        await MainActor.run {
            isSystemLoading = true
            self.alertCenter.dismiss()
        }

        do {
            _ = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "restart"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .running
            }

            Log.containers.debug("Container system restarted successfully")
            await loadContainers()

        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to restart system: \(error.localizedDescription)")
                self.isSystemLoading = false
            }
            Log.containers.error("Error restarting system: \(error.localizedDescription)")
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

    func inspectImage(reference: String) async throws -> ImageInspection {
        try await backend.inspectImage(reference: reference)
    }

    // MARK: - DNS Management

    func loadDNSDomains() async {
        await loadDNSDomains(showLoading: false)
    }

    func loadDNSDomains(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isDNSLoading = true
                self.alertCenter.dismiss()
            }
        }

        // Load system properties first to get the default domain
        await loadSystemProperties(showLoading: false)

        do {
            // Get list of domains in JSON format
            let listResult = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "dns", "ls", "--format=json"])

            if let output = listResult.stdout {
                // Get the current default domain from system properties
                let currentDefaultDomain = self.systemProperties.first(where: { $0.id == "dns.domain" })?.value
                let domains = parseDNSDomains(json: output, defaultDomain: currentDefaultDomain)
                await MainActor.run {
                    self.dnsDomains = domains
                    self.isDNSLoading = false
                }
            }
        } catch {
            await MainActor.run {
                if showLoading {
                    self.alertCenter.error("Failed to load DNS domains: \(error.localizedDescription)")
                }
                self.isDNSLoading = false
            }
        }
    }

    @discardableResult
    func createDNSDomain(_ domain: String) async -> Bool {
        do {
            let result = try await runner.runWithSudo(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "dns", "create", domain])

            if !result.failed {
                await loadDNSDomains()
                return true
            } else {
                await MainActor.run {
                    self.alertCenter.error(result.stderr ?? "Failed to create DNS domain")
                }
                return false
            }
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to create DNS domain: \(error.localizedDescription)")
            }
            return false
        }
    }

    func deleteDNSDomain(_ domain: String) async {
        do {
            let result = try await runner.runWithSudo(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "dns", "delete", domain])

            if !result.failed {
                await loadDNSDomains()
            } else {
                await MainActor.run {
                    self.alertCenter.error(result.stderr ?? "Failed to delete DNS domain")
                }
            }
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to delete DNS domain: \(error.localizedDescription)")
            }
        }
    }

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

    // MARK: - Kernel Management

    func loadKernelConfig() async {
        await MainActor.run {
            isKernelLoading = true
        }

        do {
            let kernelsDir = NSHomeDirectory() + "/Library/Application Support/com.apple.container/kernels/"
            let fileManager = FileManager.default

            // Check for both architectures
            let arm64KernelPath = kernelsDir + "default.kernel-arm64"
            let amd64KernelPath = kernelsDir + "default.kernel-amd64"

            var kernelPath: String?
            var arch: KernelArch = .arm64

            if fileManager.fileExists(atPath: arm64KernelPath) {
                kernelPath = arm64KernelPath
                arch = .arm64
            } else if fileManager.fileExists(atPath: amd64KernelPath) {
                kernelPath = amd64KernelPath
                arch = .amd64
            }

            if let kernelPath = kernelPath {
                // Try to resolve the symlink to see what kernel is active
                let resolvedPath = try fileManager.destinationOfSymbolicLink(atPath: kernelPath)

                // Check if it's the recommended kernel (contains vmlinux pattern)
                if resolvedPath.contains("vmlinux-") {
                    await MainActor.run {
                        self.kernelConfig = KernelConfig(arch: arch, isRecommended: true)
                        self.isKernelLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.kernelConfig = KernelConfig(binary: resolvedPath, arch: arch)
                        self.isKernelLoading = false
                    }
                }
            } else {
                await MainActor.run {
                    self.kernelConfig = KernelConfig()
                    self.isKernelLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.kernelConfig = KernelConfig()
                self.isKernelLoading = false
            }
        }
    }

    func setRecommendedKernel() async {
        await MainActor.run {
            isKernelLoading = true
        }

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "kernel", "set", "--recommended"])

            if !result.failed {
                await MainActor.run {
                    self.kernelConfig = KernelConfig(isRecommended: true)
                    self.isKernelLoading = false
                }
            } else {
                // Check if the error is due to kernel already being installed
                let errorOutput = result.stderr ?? ""
                if errorOutput.contains("item with the same name already exists") ||
                   errorOutput.contains("File exists") {
                    // Treat this as success - kernel is already installed
                    await MainActor.run {
                        self.kernelConfig = KernelConfig(isRecommended: true)
                        self.isKernelLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.alertCenter.error(result.stderr ?? "Failed to set recommended kernel")
                        self.isKernelLoading = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to set recommended kernel: \(error.localizedDescription)")
                self.isKernelLoading = false
            }
        }
    }

    func setCustomKernel(binary: String?, tar: String?, arch: KernelArch) async {
        await MainActor.run {
            isKernelLoading = true
        }

        do {
            var arguments = ["system", "kernel", "set", "--arch", arch.rawValue]

            if let binary = binary, !binary.isEmpty {
                arguments.append(contentsOf: ["--binary", binary])
            }

            if let tar = tar, !tar.isEmpty {
                arguments.append(contentsOf: ["--tar", tar])
            }

            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: arguments)

            if !result.failed {
                await MainActor.run {
                    self.kernelConfig = KernelConfig(binary: binary, tar: tar, arch: arch, isRecommended: false)
                    self.isKernelLoading = false
                }
            } else {
                await MainActor.run {
                    self.alertCenter.error(result.stderr ?? "Failed to set custom kernel")
                    self.isKernelLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to set custom kernel: \(error.localizedDescription)")
                self.isKernelLoading = false
            }
        }
    }



    // MARK: - System Properties Management

    func loadSystemProperties() async {
        await loadSystemProperties(showLoading: false)
    }

    func loadSystemProperties(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isSystemPropertiesLoading = true
                self.alertCenter.dismiss()
            }
        }

        var result: ProcessResult
        do {
            result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "property", "list", "--format=json"])
        } catch {
            result = ProcessResult(exitCode: -1, stdout: nil, stderr: error.localizedDescription)
        }

        if result.failed {
            await MainActor.run {
                self.alertCenter.error(result.stderr ?? "Failed to load system properties")
                self.isSystemPropertiesLoading = false
            }
            return
        }

        guard let output = result.stdout else {
            await MainActor.run {
                self.systemProperties = []
                self.isSystemPropertiesLoading = false
            }
            return
        }

        let properties = parseSystemProperties(json: output)
        await MainActor.run {
            self.systemProperties = properties
            self.isSystemPropertiesLoading = false
        }
    }

    func setSystemProperty(_ id: String, value: String) async {
        // Preserve window focus
        let currentApp = NSApplication.shared
        let isActive = currentApp.isActive

        // Optimistically update the UI first
        await MainActor.run {
            if id == "dns.domain" {
                // Update system properties optimistically
                if let index = self.systemProperties.firstIndex(where: { $0.id == id }) {
                    self.systemProperties[index] = SystemProperty(
                        id: id,
                        type: self.systemProperties[index].type,
                        value: value,
                        description: self.systemProperties[index].description
                    )
                }

                // Update DNS domains default status optimistically
                for i in 0..<self.dnsDomains.count {
                    self.dnsDomains[i] = DNSDomain(
                        domain: self.dnsDomains[i].domain,
                        isDefault: self.dnsDomains[i].domain == value
                    )
                }
            }
        }

        var result: ProcessResult
        do {
            // Execute command with focus preservation
            result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "property", "set", id, value])
        } catch {
            result = ProcessResult(exitCode: -1, stdout: nil, stderr: error.localizedDescription)
        }

        // Restore focus if it was lost
        await MainActor.run {
            if isActive && !currentApp.isActive {
                currentApp.activate(ignoringOtherApps: true)
            }
        }

        if result.failed {
            await MainActor.run {
                self.alertCenter.error(result.stderr ?? "Failed to set system property")
            }
            // Revert optimistic changes on failure
            if id == "dns.domain" {
                await loadSystemProperties(showLoading: false)
                await loadDNSDomains(showLoading: false)
            }
            return
        }

        // Success - optionally refresh in background to ensure consistency
        DispatchQueue.global(qos: .background).async { [weak self] in
            Task {
                await self?.loadSystemProperties(showLoading: false)
                if id == "dns.domain" {
                    await self?.loadDNSDomains(showLoading: false)
                }
            }
        }
    }

    func setDefaultDNSDomain(_ domain: String) async {
        // Immediate UI update without subprocess for better focus handling
        await MainActor.run {
            // Update system properties optimistically
            if let index = self.systemProperties.firstIndex(where: { $0.id == "dns.domain" }) {
                self.systemProperties[index] = SystemProperty(
                    id: "dns.domain",
                    type: self.systemProperties[index].type,
                    value: domain,
                    description: self.systemProperties[index].description
                )
            }

            // Update DNS domains default status immediately
            for i in 0..<self.dnsDomains.count {
                self.dnsDomains[i] = DNSDomain(
                    domain: self.dnsDomains[i].domain,
                    isDefault: self.dnsDomains[i].domain == domain
                )
            }
        }

        // Execute command in background without capturing self in a concurrently-executing closure
        let binaryPath = self.settings.safeContainerBinaryPath()
        let selectedDomain = domain
        let weakSelf = self

        DispatchQueue.global(qos: .userInitiated).async {
            Task { @MainActor in
                // Switch to a nonisolated copy to avoid capturing main-actor state in concurrent context
                let service = weakSelf
                do {
                    let result = try await service.runner.run(
                        program: binaryPath,
                        arguments: ["system", "property", "set", "dns.domain", selectedDomain])

                    if result.failed {
                        // Revert on failure
                        await service.loadSystemProperties(showLoading: false)
                        await service.loadDNSDomains(showLoading: false)

                        service.alertCenter.error(result.stderr ?? "Failed to set default DNS domain")
                    }
                } catch {
                    // Revert on error
                    await service.loadSystemProperties(showLoading: false)
                    await service.loadDNSDomains(showLoading: false)

                    service.alertCenter.error("Failed to set default DNS domain: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Image Pull Management

    func pullImage(_ imageName: String) async {
        let cleanImageName = imageName.trimmingCharacters(in: .whitespacesAndNewlines)

        await MainActor.run {
            pullProgress[cleanImageName] = ImagePullProgress(
                imageName: cleanImageName,
                status: .pulling,
                progress: 0.0,
                message: "Pulling image..."
            )
        }

        do {
            try await backend.pullImage(reference: cleanImageName)

            await MainActor.run {
                pullProgress[cleanImageName] = ImagePullProgress(
                    imageName: cleanImageName,
                    status: .completed,
                    progress: 1.0,
                    message: "Pull completed successfully"
                )

                Task {
                    await loadImages()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.pullProgress.removeValue(forKey: cleanImageName)
                }
            }
        } catch {
            await MainActor.run {
                let errorMsg = error.localizedDescription
                pullProgress[cleanImageName] = ImagePullProgress(
                    imageName: cleanImageName,
                    status: .failed(errorMsg),
                    progress: 0.0,
                    message: "Pull failed: \(errorMsg)"
                )
                self.alertCenter.error("Failed to pull image: \(errorMsg)")
            }
        }
    }

    // MARK: - Registry Search

    func searchImages(_ query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
            }
            return
        }

        await MainActor.run {
            isSearching = true
        }

        // Use Docker Hub API to search for images
        do {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let urlString = "https://hub.docker.com/v2/search/repositories/?query=\(encodedQuery)&page_size=25"

            guard let url = URL(string: urlString) else {
                await MainActor.run {
                    isSearching = false
                    self.alertCenter.error("Invalid search query")
                }
                return
            }

            let (data, _) = try await URLSession.shared.data(from: url)

            let searchResults = parseDockerHubSearch(data: data)
            await MainActor.run {
                self.searchResults = searchResults
                self.isSearching = false
            }
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to search images: \(error.localizedDescription)")
                self.isSearching = false
                self.searchResults = []
            }
        }
    }

    func clearSearchResults() {
        searchResults = []
    }

    // MARK: - Container Terminal (forwarded to TerminalLauncher)

    func openTerminal(for containerId: String, shell: String = "sh") {
        terminalLauncher.openTerminal(for: containerId, shell: shell)
    }

    func openTerminalWithBash(for containerId: String) {
        terminalLauncher.openTerminalWithBash(for: containerId)
    }

    // MARK: - Image Management

    func deleteImage(_ imageReference: String) async {
        await MainActor.run {
            self.alertCenter.dismiss()
        }

        do {
            try await backend.deleteImage(reference: imageReference)

            await MainActor.run {
                self.images.removeAll { $0.reference == imageReference }

                Task {
                    await loadImages()
                }
            }
        } catch {
            await MainActor.run {
                self.alertCenter.error("Failed to delete image: \(error.localizedDescription)")
            }
        }
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

