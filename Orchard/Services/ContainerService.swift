import Foundation
import SwiftUI
import AppKit
import ContainerAPIClient
import ContainerResource
import ContainerizationOCI
import ContainerizationExtras

// MARK: - Process execution (replaces SwiftExec)

struct ProcessResult {
    let exitCode: Int32
    let stdout: String?
    let stderr: String?
    var failed: Bool { exitCode != 0 }
}

func runProcess(program: String, arguments: [String]) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: program)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    var stdoutStr = String(data: stdoutData, encoding: .utf8)
    var stderrStr = String(data: stderrData, encoding: .utf8)

    // Strip trailing newline
    if let s = stdoutStr, s.hasSuffix("\n") { stdoutStr = String(s.dropLast()) }
    if let s = stderrStr, s.hasSuffix("\n") { stderrStr = String(s.dropLast()) }

    return ProcessResult(exitCode: process.terminationStatus, stdout: stdoutStr, stderr: stderrStr)
}

@MainActor
class ContainerService: ObservableObject {
    // Version is now obtained from ClientHealthCheck.ping()

    @Published var containers: [Container] = []
    @Published var images: [ContainerImage] = []
    @Published var builders: [Builder] = []
    @Published var isLoading: Bool = false
    @Published var isImagesLoading: Bool = false
    @Published var isBuildersLoading: Bool = false
    @Published var errorMessage: String?
    @Published var systemStatus: SystemStatus = .unknown
    @Published var systemStatusVersionOverride: Bool = false
    @Published var isSystemLoading = false
    @Published var loadingContainers: Set<String> = []
    @Published var containerVersion: String?
    @Published var parsedContainerVersion: String?
    @Published var isBuilderLoading = false
    @Published var builderStatus: BuilderStatus = .stopped
    @Published var dnsDomains: [DNSDomain] = []
    @Published var isDNSLoading = false
    @Published var networks: [ContainerNetwork] = []
    @Published var isNetworksLoading = false
    @Published var kernelConfig: KernelConfig = KernelConfig()
    @Published var isKernelLoading = false
    @Published var successMessage: String?
    @Published var customBinaryPath: String?
    @Published var containerStats: [ContainerStats] = []
    @Published var isStatsLoading: Bool = false
    @Published var systemDiskUsage: SystemDiskUsage? = nil
    @Published var isSystemDiskUsageLoading: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var isCheckingForUpdates: Bool = false
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

    private let defaultBinaryPath = "/usr/local/bin/container"
    private let customBinaryPathKey = "OrchardCustomBinaryPath"
    private let lastUpdateCheckKey = "OrchardLastUpdateCheck"

    // App version info
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.7"
    let githubRepo = "container-compose/orchard" // Replace with actual repo
    private let updateCheckInterval: TimeInterval = 1 * 60 * 60 // 1 hour

    var containerBinaryPath: String {
        let path = customBinaryPath ?? defaultBinaryPath
        return validateBinaryPath(path) ? path : defaultBinaryPath
    }

    var isUsingCustomBinary: Bool {
        guard let customPath = customBinaryPath else { return false }
        return customPath != defaultBinaryPath && validateBinaryPath(customPath)
    }



    init() {
        loadCustomBinaryPath()
    }

    private func loadCustomBinaryPath() {
        let userDefaults = UserDefaults.standard
        if let savedPath = userDefaults.string(forKey: customBinaryPathKey), !savedPath.isEmpty {
            customBinaryPath = savedPath
        }
    }

    func setCustomBinaryPath(_ path: String?) {
        customBinaryPath = path
        let userDefaults = UserDefaults.standard
        if let path = path, !path.isEmpty {
            userDefaults.set(path, forKey: customBinaryPathKey)
        } else {
            userDefaults.removeObject(forKey: customBinaryPathKey)
        }
    }

    func resetToDefaultBinary() {
        setCustomBinaryPath(nil)
    }

    func validateAndSetCustomBinaryPath(_ path: String?) -> Bool {
        guard let path = path, !path.isEmpty else {
            setCustomBinaryPath(nil)
            return true
        }

        if validateBinaryPath(path) {
            // If the selected path is the same as default, treat it as default
            if path == defaultBinaryPath {
                setCustomBinaryPath(nil)
            } else {
                setCustomBinaryPath(path)
            }
            return true
        } else {
            return false
        }
    }

    // MARK: - Update Management

    func checkForUpdates() async {
        await MainActor.run {
            isCheckingForUpdates = true
        }

        do {
            let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {

                let latestVersion = tagName.replacingOccurrences(of: "v", with: "")

                await MainActor.run {
                    self.latestVersion = latestVersion
                    self.updateAvailable = self.isNewerVersion(latestVersion, than: self.currentVersion)
                    self.isCheckingForUpdates = false

                    // Store last check time
                    UserDefaults.standard.set(Date(), forKey: self.lastUpdateCheckKey)
                }
            }
        } catch {
            await MainActor.run {
                self.isCheckingForUpdates = false
                print("Failed to check for updates: \(error)")
            }
        }
    }

    private func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        let v1Components = version1.components(separatedBy: ".").compactMap { Int($0) }
        let v2Components = version2.components(separatedBy: ".").compactMap { Int($0) }

        let maxCount = max(v1Components.count, v2Components.count)

        for i in 0..<maxCount {
            let v1Value = i < v1Components.count ? v1Components[i] : 0
            let v2Value = i < v2Components.count ? v2Components[i] : 0

            if v1Value > v2Value {
                return true
            } else if v1Value < v2Value {
                return false
            }
        }

        return false
    }

    func shouldCheckForUpdates() -> Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) > updateCheckInterval
    }

    func openReleasesPage() {
        if let url = URL(string: "https://github.com/\(githubRepo)/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    func checkForUpdatesManually() async {
        await checkForUpdates()

        await MainActor.run {
            if self.updateAvailable {
                self.successMessage = "Update available! Version \(self.latestVersion ?? "") is now available for download."
            } else {
                self.successMessage = "Orchard is up to date. You're running the latest version (\(self.currentVersion))."
            }
        }
    }

    private func validateBinaryPath(_ path: String) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Check if file exists and is not a directory
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        // Check if file is executable
        guard fileManager.isExecutableFile(atPath: path) else {
            return false
        }

        return true
    }

    private func safeContainerBinaryPath() -> String {
        let currentPath = customBinaryPath ?? defaultBinaryPath

        if validateBinaryPath(currentPath) {
            return currentPath
        } else {
            // Reset to default if custom path is invalid
            if customBinaryPath != nil {
                DispatchQueue.main.async {
                    self.customBinaryPath = nil
                    self.errorMessage = "Invalid binary path detected. Reset to default: \(self.defaultBinaryPath)"
                }
                UserDefaults.standard.removeObject(forKey: customBinaryPathKey)
            }
            return defaultBinaryPath
        }
    }

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

    enum BuilderStatus {
        case stopped
        case running

        var color: Color {
            switch self {
            case .stopped:
                return .gray
            case .running:
                return .green
            }
        }

        var text: String {
            switch self {
            case .stopped:
                return "Stopped"
            case .running:
                return "Running"
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
                errorMessage = nil
            }
        }

        do {
            let client = ContainerClient()
            let snapshots = try await client.list()
            let newContainers = snapshots.map { mapContainer($0) }

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
                print("Container: \(container.configuration.id), Status: \(container.status)")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            print(error)
        }
    }

    func loadImages() async {
        await MainActor.run {
            isImagesLoading = true
            errorMessage = nil
        }

        do {
            let clientImages = try await ClientImage.list()
            let newImages = clientImages.map { mapClientImage($0) }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.images = newImages
                }
                self.isImagesLoading = false
            }

            for image in newImages {
                print("Image: \(image.reference)")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isImagesLoading = false
            }
            print(error)
        }
    }

    func loadBuilders() async {
        await MainActor.run {
            isBuildersLoading = true
            errorMessage = nil
        }

        var result: ProcessResult
        do {
            result = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["builder", "status", "--format", "json"]
            )
        } catch {
            result = ProcessResult(exitCode: -1, stdout: nil, stderr: error.localizedDescription)
        }

        if result.failed {
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            if let stderr = result.stderr, !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Builder status command failed (exit \(result.exitCode)). Stderr:\n\(stderr)")
            } else if let stderr2 = result.stderr {
                print("Builder status command failed: \(stderr2)")
            } else {
                print("Builder status command failed with unknown error.")
            }
            return
        }

        let raw = result.stdout ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Known non-JSON "not running" output
        if lower.hasPrefix("builder is not running") || lower.hasPrefix("no builder") {
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            print("Builder status indicates not running (plain text).")
            return
        }

        // Empty or explicit empty JSON
        if trimmed.isEmpty || trimmed == "null" || trimmed == "[]" {
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            if trimmed.isEmpty {
                print("Builder status returned empty output; assuming no builder.")
            } else {
                print("Builder status returned \(trimmed); no builder present.")
            }
            return
        }

        // Try decoding JSON (single object or array)
        do {
            let data = Data(trimmed.utf8)

            if let single = try? JSONDecoder().decode(Builder.self, from: data) {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.builders = [single]
                    }
                    self.builderStatus = single.status.lowercased() == "running" ? .running : .stopped
                    self.isBuildersLoading = false
                }
                print("Builder: \(single.configuration.id), Status: \(single.status)")
                return
            }

            let array = try JSONDecoder().decode([Builder].self, from: data)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.builders = array
                }
                if let first = array.first {
                    self.builderStatus = first.status.lowercased() == "running" ? .running : .stopped
                } else {
                    self.builderStatus = .stopped
                }
                self.isBuildersLoading = false
            }
            for b in array {
                print("Builder: \(b.configuration.id), Status: \(b.status)")
            }
        } catch {
            let preview = String(trimmed.prefix(200))
            print("Failed to decode builder status. Error: \(error)\nStdout preview (first 200 chars):\n\(preview)")
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
        }
    }

    // MARK: - Container Stats Management

    func loadContainerStats() async {
        await loadContainerStats(showLoading: true)
    }

    func loadContainerStats(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isStatsLoading = true
                errorMessage = nil
            }
        }

        let client = ContainerClient()
        let runningContainers = containers.filter { $0.status == "running" }

        var allStats: [Orchard.ContainerStats] = []
        for container in runningContainers {
            if let stats = try? await client.stats(id: container.configuration.id) {
                allStats.append(mapContainerStats(stats))
            }
        }

        await MainActor.run {
            self.containerStats = allStats
            self.isStatsLoading = false
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
            let stats = try await ClientDiskUsage.get()
            let diskUsage = mapDiskUsageStats(stats)

            await MainActor.run {
                self.systemDiskUsage = diskUsage
                self.isSystemDiskUsageLoading = false
            }
        } catch {
            await MainActor.run {
                self.systemDiskUsage = nil
                self.isSystemDiskUsageLoading = false
                self.errorMessage = "Failed to load system disk usage: \(error.localizedDescription)"
            }
        }
    }

    private func areContainersEqual(_ old: [Container], _ new: [Container]) -> Bool {
        return old == new
    }

    func forceStopContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            errorMessage = nil
        }

        do {
            let client = ContainerClient()
            try await client.kill(id: id, signal: 9)

            await MainActor.run {
                print("Container \(id) force stop (SIGKILL) sent")
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
                self.errorMessage = "Failed to force stop container: \(error.localizedDescription)"
            }
            print("Error force stopping container: \(error)")
        }
    }

    func stopContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            errorMessage = nil
        }

        do {
            let client = ContainerClient()
            try await client.stop(id: id)

            await MainActor.run {
                print("Container \(id) stop command sent successfully")
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
                self.errorMessage = "Failed to stop container: \(error.localizedDescription)"
            }
            print("Error stopping container: \(error)")
        }
    }

    func checkSystemStatus() async {
        do {
            let health = try await ClientHealthCheck.ping()

            await MainActor.run {
                self.containerVersion = health.apiServerVersion
                self.parsedContainerVersion = health.apiServerVersion
                self.systemStatus = .running
            }
        } catch {
            await MainActor.run {
                self.containerVersion = nil
                self.parsedContainerVersion = nil
                self.systemStatus = .stopped
            }
        }
    }

    func checkSystemStatusIgnoreVersion() async {
        self.systemStatusVersionOverride = true
        await checkSystemStatus()
    }

    func checkContainerVersion() async {
        // Version is now obtained via ClientHealthCheck.ping() in checkSystemStatus()
        await checkSystemStatus()
    }

    func startSystem() async {
        await MainActor.run {
            isSystemLoading = true
            errorMessage = nil
        }

        do {
            _ = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["system", "start"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .running
            }

            print("Container system started successfully")
            await loadContainers()

        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to start system: \(error.localizedDescription)"
                self.isSystemLoading = false
            }
            print("Error starting system: \(error)")
        }
    }

    func stopSystem() async {
        await MainActor.run {
            isSystemLoading = true
            errorMessage = nil
        }

        do {
            _ = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["system", "stop"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .stopped
                self.containers.removeAll()
            }

            print("Container system stopped successfully")

        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to stop system: \(error.localizedDescription)"
                self.isSystemLoading = false
            }
            print("Error stopping system: \(error)")
        }
    }

    func restartSystem() async {
        await MainActor.run {
            isSystemLoading = true
            errorMessage = nil
        }

        do {
            _ = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["system", "restart"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .running
            }

            print("Container system restarted successfully")
            await loadContainers()

        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to restart system: \(error.localizedDescription)"
                self.isSystemLoading = false
            }
            print("Error restarting system: \(error)")
        }
    }

    func startContainer(_ id: String) async {
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
            print("DEBUG: Container \(id) operation already in progress, ignoring duplicate call")
            return
        }

        await startContainerWithRetry(id, maxRetries: 3, retryDelay: 1.0)
    }

    private func startContainerWithRetry(_ id: String, maxRetries: Int, retryDelay: TimeInterval) async {
        await MainActor.run {
            loadingContainers.insert(id)
            errorMessage = nil
        }

        let client = ContainerClient()

        for attempt in 1...maxRetries {
            do {
                let stdio: [FileHandle?] = [nil, nil, nil]
                let process = try await client.bootstrap(id: id, stdio: stdio)
                try await process.start()

                await MainActor.run {
                    print("Container \(id) start command sent successfully (attempt \(attempt))")
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
                print("Container \(id) failed to start (attempt \(attempt)): \(errorMsg)")

                let containerNotFound = errorMsg.contains("not found")
                let isTransitionError = errorMsg.contains("shuttingDown") ||
                                      errorMsg.contains("invalidState") ||
                                      errorMsg.contains("expected to be in created state")

                if containerNotFound {
                    print("Container \(id) was auto-removed by runtime, attempting automatic recovery...")

                    if await recoverContainer(id) {
                        print("Container \(id) successfully recovered, retrying start...")
                        continue
                    } else {
                        await MainActor.run {
                            print("Container \(id) recovery failed")
                            self.errorMessage = "Container was automatically removed and could not be recovered. Original configuration may be lost."
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
                            self.errorMessage = "Container failed to start after \(maxRetries) attempts. The container may be corrupted."
                            loadingContainers.remove(id)
                        }

                        Task {
                            await loadContainers()
                        }
                        return
                    } else {
                        await MainActor.run {
                            self.errorMessage = "Container is in transition state, retrying..."
                        }
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Failed to start container: \(errorMsg)"
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
                    print("Checking stop status for \(id): \(container.status)")
                    return container.status.lowercased() != "running"
                } else {
                    print("Container \(id) not found, assuming stopped")
                    return true  // Container not found, assume it stopped
                }
            }

            if shouldStop {
                await MainActor.run {
                    print("Container \(id) has stopped, removing loading state")
                    loadingContainers.remove(id)
                }
                return
            }

            attempts += 1
            print("Container \(id) still running, attempt \(attempts)/\(maxAttempts)")
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }

        // Timeout reached, remove loading state
        await MainActor.run {
            print("Timeout reached for container \(id), removing loading state")
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
                    print("Checking start status for \(id): \(container.status)")
                    return container.status.lowercased() == "running"
                }
                return false
            }

            if isRunning {
                await MainActor.run {
                    print("Container \(id) has started, removing loading state")
                    loadingContainers.remove(id)
                }
                return
            }

            attempts += 1
            print("Container \(id) not running yet, attempt \(attempts)/\(maxAttempts)")
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }

        // Timeout reached, remove loading state
        await MainActor.run {
            print("Timeout reached for container \(id), removing loading state")
            loadingContainers.remove(id)
        }
    }

    func startBuilder() async {
        await MainActor.run {
            isBuilderLoading = true
            errorMessage = nil
        }

        var result: ProcessResult
        do {
            result = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["builder", "start"])

            await MainActor.run {
                if !result.failed {
                    print("Builder start command sent successfully")
                    self.isBuilderLoading = false
                    // Refresh builder status
                    Task {
                        await loadBuilders()
                    }
                } else {
                    self.errorMessage =
                        "Failed to start builder: \(result.stderr ?? "Unknown error")"
                    self.isBuilderLoading = false
                }
            }

        } catch {
            await MainActor.run {
                self.isBuilderLoading = false
                self.errorMessage = "Failed to start builder: \(error.localizedDescription)"
            }
            print("Error starting builder: \(error)")
        }
    }

    func stopBuilder() async {
        await MainActor.run {
            isBuilderLoading = true
            errorMessage = nil
        }

        var result: ProcessResult
        do {
            result = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["builder", "stop"])

            await MainActor.run {
                if !result.failed {
                    print("Builder stop command sent successfully")
                    self.isBuilderLoading = false
                    // Refresh builder status
                    Task {
                        await loadBuilders()
                    }
                } else {
                    self.errorMessage =
                        "Failed to stop builder: \(result.stderr ?? "Unknown error")"
                    self.isBuilderLoading = false
                }
            }

        } catch {
            await MainActor.run {
                self.isBuilderLoading = false
                self.errorMessage = "Failed to stop builder: \(error.localizedDescription)"
            }
            print("Error stopping builder: \(error)")
        }
    }

    func deleteBuilder() async {
        await MainActor.run {
            isBuilderLoading = true
            errorMessage = nil
        }

        var result: ProcessResult
        do {
            result = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["builder", "delete"])

            await MainActor.run {
                if !result.failed {
                    print("Builder delete command sent successfully")
                    self.isBuilderLoading = false
                    // Clear builders array since it was deleted
                    self.builders = []
                } else {
                    self.errorMessage =
                        "Failed to delete builder: \(result.stderr ?? "Unknown error")"
                    self.isBuilderLoading = false
                }
            }

        } catch {
            await MainActor.run {
                self.isBuilderLoading = false
                self.errorMessage = "Failed to delete builder: \(error.localizedDescription)"
            }
            print("Error deleting builder: \(error)")
        }
    }

    func removeContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            errorMessage = nil
        }

        do {
            let client = ContainerClient()
            try await client.delete(id: id)

            await MainActor.run {
                print("Container \(id) remove command sent successfully")
                Task {
                    await loadBuilders()
                }
                self.containers.removeAll { $0.configuration.id == id }
                loadingContainers.remove(id)
            }
        } catch {
            await MainActor.run {
                loadingContainers.remove(id)
                self.errorMessage = "Failed to remove container: \(error.localizedDescription)"
            }
            print("Error removing container: \(error)")
        }
    }

    func fetchContainerLogs(containerId: String, tailLines: Int = 5000) async throws -> [String] {
        let client = ContainerClient()
        let fileHandles = try await client.logs(id: containerId)

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

    // MARK: - DNS Management

    func loadDNSDomains() async {
        await loadDNSDomains(showLoading: false)
    }

    func loadDNSDomains(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isDNSLoading = true
                errorMessage = nil
            }
        }

        // Load system properties first to get the default domain
        await loadSystemProperties(showLoading: false)

        do {
            // Get list of domains in JSON format
            let listResult = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["system", "dns", "ls", "--format=json"])

            if let output = listResult.stdout {
                // Get the current default domain from system properties
                let currentDefaultDomain = self.systemProperties.first(where: { $0.id == "dns.domain" })?.value
                let domains = parseDNSDomainsFromJSON(output, defaultDomain: currentDefaultDomain)
                await MainActor.run {
                    self.dnsDomains = domains
                    self.isDNSLoading = false
                }
            }
        } catch {
            await MainActor.run {
                if showLoading {
                    self.errorMessage = "Failed to load DNS domains: \(error.localizedDescription)"
                }
                self.isDNSLoading = false
            }
        }
    }

    func createDNSDomain(_ domain: String) async {
        do {
            let result = try execWithSudo(
                program: safeContainerBinaryPath(),
                arguments: ["system", "dns", "create", domain])

            if !result.failed {
                await loadDNSDomains()
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to create DNS domain"
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to create DNS domain: \(error.localizedDescription)"
            }
        }
    }

    func deleteDNSDomain(_ domain: String) async {
        do {
            let result = try execWithSudo(
                program: safeContainerBinaryPath(),
                arguments: ["system", "dns", "delete", domain])

            if !result.failed {
                await loadDNSDomains()
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to delete DNS domain"
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete DNS domain: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Network Management

    func loadNetworks() async {
        await loadNetworks(showLoading: false)
    }

    func loadNetworks(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isNetworksLoading = true
                errorMessage = nil
            }
        }

        do {
            let networkStates = try await ClientNetwork.list()
            let networks = networkStates.map { mapNetworkState($0) }

            await MainActor.run {
                self.networks = networks
                self.isNetworksLoading = false
            }
        } catch {
            await MainActor.run {
                if showLoading {
                    self.errorMessage = "Failed to load networks: \(error.localizedDescription)"
                }
                self.isNetworksLoading = false
            }
        }
    }

    func createNetwork(name: String, subnet: String? = nil, labels: [String] = []) async {
        do {
            var labelDict: [String: String] = [:]
            for label in labels {
                let parts = label.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    labelDict[String(parts[0])] = String(parts[1])
                } else {
                    labelDict[label] = ""
                }
            }

            let config = try NetworkConfiguration(
                id: name,
                mode: .nat,
                labels: labelDict,
                pluginInfo: NetworkPluginInfo(plugin: "apple")
            )

            _ = try await ClientNetwork.create(configuration: config)

            await MainActor.run {
                self.successMessage = "Network '\(name)' created successfully"
                self.errorMessage = nil

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.successMessage = nil
                }
            }
            await loadNetworks()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to create network: \(error.localizedDescription)"
            }
        }
    }

    func deleteNetwork(_ networkId: String) async {
        do {
            try await ClientNetwork.delete(id: networkId)

            await MainActor.run {
                self.successMessage = "Network '\(networkId)' deleted successfully"
                self.errorMessage = nil

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.successMessage = nil
                }
            }
            await loadNetworks()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete network: \(error.localizedDescription)"
            }
        }
    }

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
            let result = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["system", "kernel", "set", "--recommended"])

            if !result.failed {
                await MainActor.run {
                    self.kernelConfig = KernelConfig(isRecommended: true)
                    self.successMessage = "Recommended kernel has been installed and configured successfully."
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
                        self.successMessage = "The recommended kernel is already installed and active."
                        self.isKernelLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = result.stderr ?? "Failed to set recommended kernel"
                        self.isKernelLoading = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to set recommended kernel: \(error.localizedDescription)"
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

            let result = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: arguments)

            if !result.failed {
                await MainActor.run {
                    self.kernelConfig = KernelConfig(binary: binary, tar: tar, arch: arch, isRecommended: false)
                    self.successMessage = "Custom kernel has been configured successfully."
                    self.isKernelLoading = false
                }
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to set custom kernel"
                    self.isKernelLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to set custom kernel: \(error.localizedDescription)"
                self.isKernelLoading = false
            }
        }
    }



    private func parseDNSDomainsFromJSON(_ output: String, defaultDomain: String?) -> [DNSDomain] {
        var domains: [DNSDomain] = []

        do {
            guard let data = output.data(using: .utf8) else {
                return domains
            }

            // Parse JSON array of domain strings
            if let domainArray = try JSONSerialization.jsonObject(with: data) as? [String] {
                for domainName in domainArray {
                    let isDefault = domainName == defaultDomain
                    domains.append(DNSDomain(domain: domainName, isDefault: isDefault))
                }
            }
        } catch {
            // Ignore JSON parsing errors
        }

        return domains
    }

    // MARK: - System Properties Management

    func loadSystemProperties() async {
        await loadSystemProperties(showLoading: false)
    }

    func loadSystemProperties(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isSystemPropertiesLoading = true
                errorMessage = nil
            }
        }

        var result: ProcessResult
        do {
            result = try runProcess(
                program: safeContainerBinaryPath(),
                arguments: ["system", "property", "list", "--format=json"])
        } catch {
            result = ProcessResult(exitCode: -1, stdout: nil, stderr: error.localizedDescription)
        }

        if result.failed {
            await MainActor.run {
                self.errorMessage = result.stderr ?? "Failed to load system properties"
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

        let properties = parseSystemPropertiesFromOutput(output)
        await MainActor.run {
            self.systemProperties = properties
            self.isSystemPropertiesLoading = false
        }
    }

    private func parseSystemPropertiesFromOutput(_ output: String) -> [SystemProperty] {
        var properties: [SystemProperty] = []

        do {
            guard let data = output.data(using: .utf8) else {
                return properties
            }

            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for propertyDict in jsonArray {
                    guard let id = propertyDict["id"] as? String,
                          let typeString = propertyDict["type"] as? String,
                          let description = propertyDict["description"] as? String else {
                        continue
                    }

                    // Handle value which can be null, bool, or string
                    let valueString: String
                    if let value = propertyDict["value"] {
                        if value is NSNull {
                            valueString = "*undefined*"
                        } else if let boolValue = value as? Bool {
                            valueString = boolValue ? "true" : "false"
                        } else if let stringValue = value as? String {
                            valueString = stringValue
                        } else {
                            valueString = String(describing: value)
                        }
                    } else {
                        valueString = "*undefined*"
                    }

                    let type: SystemProperty.PropertyType = typeString.lowercased() == "bool" ? .bool : .string

                    properties.append(SystemProperty(
                        id: id,
                        type: type,
                        value: valueString,
                        description: description
                    ))
                }
            }
        } catch {
            print("Error parsing system properties JSON: \(error)")
        }

        return properties
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
            result = try runProcess(
                program: safeContainerBinaryPath(),
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
                self.errorMessage = result.stderr ?? "Failed to set system property"
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
        let binaryPath = self.safeContainerBinaryPath()
        let selectedDomain = domain
        let weakSelf = self

        DispatchQueue.global(qos: .userInitiated).async {
            Task { @MainActor in
                // Switch to a nonisolated copy to avoid capturing main-actor state in concurrent context
                let service = weakSelf
                do {
                    let result = try runProcess(
                        program: binaryPath,
                        arguments: ["system", "property", "set", "dns.domain", selectedDomain])

                    if result.failed {
                        // Revert on failure
                        await service.loadSystemProperties(showLoading: false)
                        await service.loadDNSDomains(showLoading: false)

                        service.errorMessage = result.stderr ?? "Failed to set default DNS domain"
                    }
                } catch {
                    // Revert on error
                    await service.loadSystemProperties(showLoading: false)
                    await service.loadDNSDomains(showLoading: false)

                    service.errorMessage = "Failed to set default DNS domain: \(error.localizedDescription)"
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
            _ = try await ClientImage.pull(reference: cleanImageName)

            await MainActor.run {
                pullProgress[cleanImageName] = ImagePullProgress(
                    imageName: cleanImageName,
                    status: .completed,
                    progress: 1.0,
                    message: "Pull completed successfully"
                )
                self.successMessage = "Successfully pulled image: \(cleanImageName)"

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
                self.errorMessage = "Failed to pull image: \(errorMsg)"
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
                    errorMessage = "Invalid search query"
                }
                return
            }

            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {

                let searchResults: [RegistrySearchResult] = results.compactMap { result in
                    guard let name = result["repo_name"] as? String else { return nil }

                    // Build full image name with registry
                    let fullName: String
                    if name.contains("/") {
                        fullName = "docker.io/\(name)"
                    } else {
                        fullName = "docker.io/library/\(name)"
                    }

                    return RegistrySearchResult(
                        name: fullName,
                        description: result["short_description"] as? String,
                        isOfficial: (result["is_official"] as? Bool) ?? false,
                        starCount: result["star_count"] as? Int
                    )
                }

                await MainActor.run {
                    self.searchResults = searchResults
                    self.isSearching = false
                }
            } else {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to search images: \(error.localizedDescription)"
                self.isSearching = false
                self.searchResults = []
            }
        }
    }

    func clearSearchResults() {
        searchResults = []
    }

    // MARK: - Container Terminal

    func openTerminal(for containerId: String, shell: String = "/bin/sh") {
        // Build the command to execute in Terminal.app
        let containerBinary = safeContainerBinaryPath()

        // Build the complete command - note: we need to quote the shell path if it has spaces
        let fullCommand = "'\(containerBinary)' exec -it '\(containerId)' \(shell)"

        // Escape for AppleScript - replace backslashes and quotes
        let escapedCommand = fullCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Create AppleScript to open Terminal with the command
        // Using 'do script' opens a new Terminal window/tab and executes the command
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        // Debug: print the command and script
        print(String(repeating: "=", count: 60))
        print("Opening terminal with:")
        print("  Binary: \(containerBinary)")
        print("  Container: \(containerId)")
        print("  Shell: \(shell)")
        print("  Full command: \(fullCommand)")
        print("  Escaped command: \(escapedCommand)")
        print(String(repeating: "=", count: 60))
        print("AppleScript:")
        print(script)
        print(String(repeating: "=", count: 60))

        // Execute the AppleScript
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)

        if let error = error {
            print("❌ AppleScript error: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to open terminal: \(error)"
            }
        } else if let result = result {
            print("✓ AppleScript executed successfully")
            print("  Result: \(result)")
        }
    }

    func openTerminalWithBash(for containerId: String) {
        openTerminal(for: containerId, shell: "/bin/bash")
    }

    // MARK: - Image Management

    func deleteImage(_ imageReference: String) async {
        await MainActor.run {
            errorMessage = nil
            successMessage = nil
        }

        do {
            try await ClientImage.delete(reference: imageReference)

            await MainActor.run {
                self.successMessage = "Successfully deleted image: \(imageReference)"
                self.images.removeAll { $0.reference == imageReference }

                Task {
                    await loadImages()
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete image: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Container Run Management

    func recreateContainer(oldContainerId: String, newConfig: ContainerRunConfig) async {
        await MainActor.run {
            errorMessage = nil
            successMessage = nil
        }

        do {
            let client = ContainerClient()
            try await client.delete(id: oldContainerId, force: true)

            await runContainer(config: newConfig)

            await MainActor.run {
                if self.errorMessage == nil {
                    self.successMessage = "Container '\(newConfig.name)' has been recreated with new configuration"
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to recreate container: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Container Recovery

    private func recoverContainer(_ id: String) async -> Bool {
        guard let snapshot = await MainActor.run(body: { containerSnapshots[id] }) else {
            print("No snapshot available for container \(id)")
            return false
        }

        print("Attempting to recover container \(id) from snapshot...")

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

        await runContainer(config: runConfig)

        let hasError = await MainActor.run(body: { self.errorMessage != nil })
        if hasError {
            print("Container recovery failed")
            return false
        } else {
            print("Container \(id) recovered successfully")
            return true
        }
    }

    /// Build an API ContainerConfiguration and create+start a container.
    private func createAndStartContainer(
        id: String,
        imageRef: String,
        environment: [String],
        workingDirectory: String,
        commandOverride: [String],
        mounts: [Filesystem],
        publishedPorts: [PublishPort],
        dns: ContainerResource.ContainerConfiguration.DNSConfiguration?,
        networkName: String,
        autoRemove: Bool
    ) async throws {
        // Fetch or pull the image
        let image = try await ClientImage.fetch(reference: imageRef)
        let platform = ContainerizationOCI.Platform.current

        // Unpack image snapshot
        try await image.getCreateSnapshot(platform: platform)

        // Get the default kernel
        let kernel = try await ClientKernel.getDefaultKernel(for: .current)

        // Get the OCI image config for entrypoint/cmd/env/user
        let imageConfig = try await image.config(for: platform).config

        // Build the process arguments: entrypoint + cmd, with user overrides
        let imageEnv = imageConfig?.env ?? []
        let mergedEnv = imageEnv + environment

        var processArgs: [String] = []
        if let entrypoint = imageConfig?.entrypoint, !entrypoint.isEmpty {
            processArgs = entrypoint
        }
        if !commandOverride.isEmpty {
            if processArgs.isEmpty {
                processArgs = commandOverride
            } else {
                processArgs.append(contentsOf: commandOverride)
            }
        } else if let cmd = imageConfig?.cmd, !cmd.isEmpty, processArgs.isEmpty || (imageConfig?.entrypoint != nil) {
            processArgs.append(contentsOf: cmd)
        }

        guard !processArgs.isEmpty else {
            throw NSError(domain: "ContainerService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No entrypoint or command specified for the container"])
        }

        let user: ProcessConfiguration.User = {
            if let u = imageConfig?.user, !u.isEmpty {
                return .raw(userString: u)
            }
            return .id(uid: 0, gid: 0)
        }()

        let wd = workingDirectory.isEmpty ? (imageConfig?.workingDir ?? "/") : workingDirectory

        let process = ProcessConfiguration(
            executable: processArgs.first!,
            arguments: Array(processArgs.dropFirst()),
            environment: mergedEnv,
            workingDirectory: wd,
            terminal: false,
            user: user
        )

        var containerConfig = ContainerResource.ContainerConfiguration(
            id: id,
            image: image.description,
            process: process
        )
        containerConfig.mounts = mounts
        containerConfig.publishedPorts = publishedPorts
        containerConfig.dns = dns

        // Set up network
        let builtinNetworkId = try await ClientNetwork.builtin?.id
        let networkId = networkName.isEmpty ? (builtinNetworkId ?? ClientNetwork.defaultNetworkName) : networkName
        containerConfig.networks = [
            AttachmentConfiguration(
                network: networkId,
                options: AttachmentOptions(hostname: id, macAddress: nil, mtu: 1280)
            )
        ]

        let client = ContainerClient()
        let options = ContainerCreateOptions(autoRemove: autoRemove)
        try await client.create(configuration: containerConfig, options: options, kernel: kernel)

        // Bootstrap and start in detached mode
        let stdio: [FileHandle?] = [nil, nil, nil]
        let proc = try await client.bootstrap(id: id, stdio: stdio)
        try await proc.start()
    }

    func runContainer(config: ContainerRunConfig) async {
        await MainActor.run {
            errorMessage = nil
            successMessage = nil
        }

        do {
            let id = config.name.isEmpty ? UUID().uuidString.lowercased().prefix(12).description : config.name

            // Build environment strings
            var envStrings: [String] = []
            for envVar in config.environmentVariables {
                if !envVar.key.isEmpty {
                    envStrings.append("\(envVar.key)=\(envVar.value)")
                }
            }

            // Build mounts
            var mounts: [Filesystem] = []
            for vol in config.volumeMappings {
                if !vol.hostPath.isEmpty && !vol.containerPath.isEmpty {
                    var options: [String] = []
                    if vol.readonly { options.append("ro") }
                    mounts.append(.virtiofs(source: vol.hostPath, destination: vol.containerPath, options: options))
                }
            }

            // Build published ports
            var ports: [PublishPort] = []
            for pm in config.portMappings {
                if let hp = UInt16(pm.hostPort), let cp = UInt16(pm.containerPort) {
                    let proto = PublishProtocol(pm.transportProtocol) ?? .tcp
                    ports.append(PublishPort(
                        hostAddress: try IPAddress("0.0.0.0"),
                        hostPort: hp,
                        containerPort: cp,
                        proto: proto,
                        count: 1
                    ))
                }
            }

            // Build DNS
            let dns: ContainerResource.ContainerConfiguration.DNSConfiguration? = {
                if config.dnsDomain.isEmpty { return nil }
                return .init(
                    nameservers: ContainerResource.ContainerConfiguration.DNSConfiguration.defaultNameservers,
                    domain: config.dnsDomain,
                    searchDomains: [],
                    options: []
                )
            }()

            // Build command override
            var commandArgs: [String] = []
            if !config.commandOverride.isEmpty {
                commandArgs = config.commandOverride.split(separator: " ").map(String.init)
            }

            try await createAndStartContainer(
                id: id,
                imageRef: config.image,
                environment: envStrings,
                workingDirectory: config.workingDirectory,
                commandOverride: commandArgs,
                mounts: mounts,
                publishedPorts: ports,
                dns: dns,
                networkName: config.network,
                autoRemove: config.removeAfterStop
            )

            await MainActor.run {
                let containerName = config.name.isEmpty ? "Container" : config.name
                self.successMessage = "Successfully started container: \(containerName)"

                Task {
                    await loadContainers()
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to run container: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sudo Helper

    private func execWithSudo(program: String, arguments: [String]) throws -> ProcessResult {
        let fullCommand = "\(program) \(arguments.joined(separator: " "))"

        let script = """
        do shell script "\(fullCommand)" with administrator privileges
        """

        return try runProcess(
            program: "/usr/bin/osascript",
            arguments: ["-e", script])
    }
}

