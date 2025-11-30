import Foundation
import SwiftExec
import SwiftUI
import AppKit

class ContainerService: ObservableObject {
    let supportedContainerVersion = "0.6.0"

    @Published var containers: [Container] = []
    @Published var images: [ContainerImage] = []
    @Published var builders: [Builder] = []
    @Published var isLoading: Bool = false
    @Published var isImagesLoading: Bool = false
    @Published var isBuildersLoading: Bool = false
    @Published var errorMessage: String?
    @Published var systemStatus: SystemStatus = .unknown
    @Published var isSystemLoading = false
    @Published var loadingContainers: Set<String> = []
    @Published var containerVersion: String?
    @Published var parsedContainerVersion: String?
    @Published var isBuilderLoading = false
    @Published var builderStatus: BuilderStatus = .stopped
    @Published var dnsDomains: [DNSDomain] = []
    @Published var isDNSLoading = false
    @Published var kernelConfig: KernelConfig = KernelConfig()
    @Published var isKernelLoading = false
    @Published var successMessage: String?
    @Published var customBinaryPath: String?
    @Published var refreshInterval: RefreshInterval = .fiveSeconds
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var isCheckingForUpdates: Bool = false
    @Published var pullProgress: [String: ImagePullProgress] = [:]
    @Published var isSearching: Bool = false
    @Published var searchResults: [RegistrySearchResult] = []
    @Published var systemProperties: [SystemProperty] = []
    @Published var isSystemPropertiesLoading = false

    private let defaultBinaryPath = "/usr/local/bin/container"
    private let customBinaryPathKey = "OrchardCustomBinaryPath"
    private let refreshIntervalKey = "OrchardRefreshInterval"
    private let lastUpdateCheckKey = "OrchardLastUpdateCheck"

    // App version info
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.7"
    let githubRepo = "container-compose/orchard" // Replace with actual repo
    private let updateCheckInterval: TimeInterval = 1 * 60 * 60 // 1 hour

    enum RefreshInterval: String, CaseIterable {
        case oneSecond = "1"
        case fiveSeconds = "5"
        case fifteenSeconds = "15"
        case thirtySeconds = "30"

        var displayName: String {
            switch self {
            case .oneSecond:
                return "1 second"
            case .fiveSeconds:
                return "5 seconds"
            case .fifteenSeconds:
                return "15 seconds"
            case .thirtySeconds:
                return "30 seconds"
            }
        }

        var timeInterval: TimeInterval {
            return TimeInterval(rawValue) ?? 5.0
        }
    }

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
        loadRefreshInterval()
    }

    private func loadCustomBinaryPath() {
        let userDefaults = UserDefaults.standard
        if let savedPath = userDefaults.string(forKey: customBinaryPathKey), !savedPath.isEmpty {
            customBinaryPath = savedPath
        }
    }

    private func loadRefreshInterval() {
        let userDefaults = UserDefaults.standard
        if let savedInterval = userDefaults.string(forKey: refreshIntervalKey),
           let interval = RefreshInterval(rawValue: savedInterval) {
            refreshInterval = interval
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

    func setRefreshInterval(_ interval: RefreshInterval) {
        refreshInterval = interval
        let userDefaults = UserDefaults.standard
        userDefaults.set(interval.rawValue, forKey: refreshIntervalKey)
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

                if var existingMount = mountDict[mountId] {
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
        case unsupportedVersion

        var color: Color {
            switch self {
            case .unknown, .stopped:
                return .gray
            case .running:
                return .green
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

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["ls", "--format", "json"])
        } catch {
            let error = error as! ExecError
            result = error.execResult
        }

        do {
            let data = result.stdout?.data(using: .utf8)
            let newContainers = try JSONDecoder().decode(
                Containers.self, from: data!)

            await MainActor.run {
                if !areContainersEqual(self.containers, newContainers) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.containers = newContainers
                    }
                }
                self.isLoading = false
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

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["image", "list", "--format", "json"])
        } catch {
            let error = error as! ExecError
            result = error.execResult
        }

        do {
            let data = result.stdout?.data(using: .utf8)
            let newImages = try JSONDecoder().decode(
                [ContainerImage].self, from: data!)

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

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["builder", "status", "--format", "json"]
            )
        } catch {
            let execError = error as? ExecError
            result = execError?.execResult ?? ExecResult(
                failed: true,
                message: error.localizedDescription,
                exitCode: nil,
                stdout: nil,
                stderr: nil
            )
        }

        if result.failed {
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            if let stderr = result.stderr, !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Builder status command failed (exit \(result.exitCode ?? -1)). Stderr:\n\(stderr)")
            } else if let message = result.message {
                print("Builder status command failed: \(message)")
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

    private func areContainersEqual(_ old: [Container], _ new: [Container]) -> Bool {
        return old == new
    }

    func stopContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            errorMessage = nil
        }

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["stop", id])

            await MainActor.run {
                if !result.failed {
                    print("Container \(id) stop command sent successfully")
                    // Immediately refresh builder status in case this container was the builder
                    Task {
                        await loadBuilders()
                    }
                    // Keep loading state and refresh containers to check status
                    Task {
                        await refreshUntilContainerStopped(id)
                    }
                } else {
                    self.errorMessage =
                        "Failed to stop container: \(result.stderr ?? "Unknown error")"
                    loadingContainers.remove(id)
                }
            }

        } catch {
            let error = error as! ExecError
            result = error.execResult

            await MainActor.run {
                loadingContainers.remove(id)
                self.errorMessage = "Failed to stop container: \(error.localizedDescription)"
            }
            print("Error stopping container: \(error)")
        }
    }

    func checkSystemStatus() async {
        // First check if container CLI is available and get version
        await checkContainerVersion()

        // If version is unsupported, don't check if system is running
        if await MainActor.run(body: { self.systemStatus }) == .unsupportedVersion {
            return
        }

        // Check if system is running
        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["ls"])

            await MainActor.run {
                // Only set to running if version is supported
                self.systemStatus = .running
            }
        } catch {
            await MainActor.run {
                self.systemStatus = .stopped
            }
        }
    }

    func checkContainerVersion() async {
        do {
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["--version"])

            let output = result.stdout

            // Parse version from output like "container CLI version 0.6.0 (build: release, commit: a23bcf0)"
            var extractedVersion: String?
            if let output = output {
                // Try regex pattern first
                let pattern = #"version\s+(\d+\.\d+\.\d+)"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(location: 0, length: output.utf16.count)
                    if let match = regex.firstMatch(in: output, options: [], range: range),
                       let versionRange = Range(match.range(at: 1), in: output) {
                        extractedVersion = String(output[versionRange])
                    }
                }

                // Fallback if regex failed
                if extractedVersion == nil {
                    let components = output.components(separatedBy: " ")
                    if let versionIndex = components.firstIndex(of: "version"),
                       versionIndex + 1 < components.count {
                        let versionCandidate = components[versionIndex + 1]
                        // Simple check for version-like format
                        let versionPattern = #"^\d+\.\d+\.\d+"#
                        if versionCandidate.range(of: versionPattern, options: .regularExpression) != nil {
                            extractedVersion = versionCandidate
                        }
                    }
                }
            }

            await MainActor.run {
                self.containerVersion = output
                self.parsedContainerVersion = extractedVersion

                if let version = extractedVersion, version == self.supportedContainerVersion {
                    // Only update to running if we're not already stopped
                    if self.systemStatus != .stopped {
                        self.systemStatus = .running
                    }
                } else {
                    self.systemStatus = .unsupportedVersion
                }
            }
        } catch {
            await MainActor.run {
                self.containerVersion = nil
                self.parsedContainerVersion = nil
                self.systemStatus = .stopped
            }
        }
    }

    func startSystem() async {
        await MainActor.run {
            isSystemLoading = true
            errorMessage = nil
        }

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "start"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .running
            }

            print("Container system started successfully")
            await loadContainers()

        } catch {
            let error = error as! ExecError
            result = error.execResult

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

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "stop"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .stopped
                self.containers.removeAll()
            }

            print("Container system stopped successfully")

        } catch {
            let error = error as! ExecError
            result = error.execResult

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

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "restart"])

            await MainActor.run {
                self.isSystemLoading = false
                self.systemStatus = .running
            }

            print("Container system restarted successfully")
            await loadContainers()

        } catch {
            let error = error as! ExecError
            result = error.execResult

            await MainActor.run {
                self.errorMessage = "Failed to restart system: \(error.localizedDescription)"
                self.isSystemLoading = false
            }
            print("Error restarting system: \(error)")
        }
    }

    func startContainer(_ id: String) async {
        await MainActor.run {
            loadingContainers.insert(id)
            errorMessage = nil
        }

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["start", id])
        } catch {
            let error = error as! ExecError
            result = error.execResult
        }

        await MainActor.run {
            if !result.failed {
                print("Container \(id) start command sent successfully")
                // Immediately refresh builder status in case this container is the builder
                Task {
                    await loadBuilders()
                }
                // Keep loading state and refresh containers to check status
                Task {
                    await refreshUntilContainerStarted(id)
                }
            } else {
                self.errorMessage = "Failed to start container: \(result.stderr ?? "Unknown error")"
                loadingContainers.remove(id)
            }
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

        var result: ExecResult
        do {
            result = try exec(
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
            let error = error as! ExecError
            result = error.execResult

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

        var result: ExecResult
        do {
            result = try exec(
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
            let error = error as! ExecError
            result = error.execResult

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

        var result: ExecResult
        do {
            result = try exec(
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
            let error = error as! ExecError
            result = error.execResult

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

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["rm", id])

            await MainActor.run {
                if !result.failed {
                    print("Container \(id) remove command sent successfully")
                    // Immediately refresh builder status in case this container was the builder
                    Task {
                        await loadBuilders()
                    }
                    // Remove from local array immediately
                    self.containers.removeAll { $0.configuration.id == id }
                    loadingContainers.remove(id)
                } else {
                    self.errorMessage =
                        "Failed to remove container: \(result.stderr ?? "Unknown error")"
                    loadingContainers.remove(id)
                }
            }

        } catch {
            let error = error as! ExecError
            result = error.execResult

            await MainActor.run {
                loadingContainers.remove(id)
                self.errorMessage = "Failed to remove container: \(error.localizedDescription)"
            }
            print("Error removing container: \(error)")
        }
    }

    func fetchContainerLogs(containerId: String) async throws -> String {
        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["logs", containerId])
        } catch {
            let error = error as! ExecError
            result = error.execResult
        }

        if let stdout = result.stdout {
            return stdout
        } else if let stderr = result.stderr {
            throw NSError(domain: "ContainerService", code: 1, userInfo: [NSLocalizedDescriptionKey: stderr])
        } else {
            return ""
        }
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

        var result: ExecResult
        do {
            // Get list of domains in JSON format
            let listResult = try exec(
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
            let result = try exec(
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

            let result = try exec(
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

        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "property", "list", "--format=json"])
        } catch {
            let error = error as! ExecError
            result = error.execResult
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

        var result: ExecResult
        do {
            // Execute command with focus preservation
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "property", "set", id, value])
        } catch {
            let error = error as! ExecError
            result = error.execResult
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

        // Execute command in background without blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Task {
                do {
                    let result = try exec(
                        program: self?.safeContainerBinaryPath() ?? "/usr/local/bin/container",
                        arguments: ["system", "property", "set", "dns.domain", domain])

                    if result.failed {
                        // Revert on failure
                        await self?.loadSystemProperties(showLoading: false)
                        await self?.loadDNSDomains(showLoading: false)

                        await MainActor.run {
                            self?.errorMessage = result.stderr ?? "Failed to set default DNS domain"
                        }
                    }
                } catch {
                    // Revert on error
                    await self?.loadSystemProperties(showLoading: false)
                    await self?.loadDNSDomains(showLoading: false)

                    await MainActor.run {
                        self?.errorMessage = "Failed to set default DNS domain: \(error.localizedDescription)"
                    }
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
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["image", "pull", cleanImageName])

            await MainActor.run {
                if !result.failed {
                    pullProgress[cleanImageName] = ImagePullProgress(
                        imageName: cleanImageName,
                        status: .completed,
                        progress: 1.0,
                        message: "Pull completed successfully"
                    )
                    self.successMessage = "Successfully pulled image: \(cleanImageName)"

                    // Refresh images list
                    Task {
                        await loadImages()
                    }

                    // Remove from progress after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.pullProgress.removeValue(forKey: cleanImageName)
                    }
                } else {
                    let errorMsg = result.stderr ?? "Unknown error"
                    pullProgress[cleanImageName] = ImagePullProgress(
                        imageName: cleanImageName,
                        status: .failed(errorMsg),
                        progress: 0.0,
                        message: "Pull failed: \(errorMsg)"
                    )
                    self.errorMessage = "Failed to pull image: \(errorMsg)"
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
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["image", "delete", imageReference])

            await MainActor.run {
                if !result.failed {
                    self.successMessage = "Successfully deleted image: \(imageReference)"

                    // Remove from local array immediately
                    self.images.removeAll { $0.reference == imageReference }

                    // Refresh images list
                    Task {
                        await loadImages()
                    }
                } else {
                    let errorMsg = result.stderr ?? "Unknown error"
                    self.errorMessage = "Failed to delete image: \(errorMsg)"
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

        // First, delete the old container
        do {
            let deleteResult = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["delete", oldContainerId])

            if deleteResult.failed {
                await MainActor.run {
                    let errorMsg = deleteResult.stderr ?? "Unknown error"
                    self.errorMessage = "Failed to delete old container: \(errorMsg)"
                }
                return
            }

            // Now create the new container with updated config
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

    func runContainer(config: ContainerRunConfig) async {
        await MainActor.run {
            errorMessage = nil
            successMessage = nil
        }

        var arguments = ["run"]

        // Add detached flag
        if config.detached {
            arguments.append("-d")
        }

        // Add remove after stop flag
        if config.removeAfterStop {
            arguments.append("--rm")
        }

        // Add container name
        if !config.name.isEmpty {
            arguments.append(contentsOf: ["--name", config.name])
        }

        // Add environment variables
        for envVar in config.environmentVariables {
            if !envVar.key.isEmpty {
                arguments.append(contentsOf: ["-e", "\(envVar.key)=\(envVar.value)"])
            }
        }

        // Add port mappings
        for portMapping in config.portMappings {
            if !portMapping.hostPort.isEmpty && !portMapping.containerPort.isEmpty {
                let mapping = "\(portMapping.hostPort):\(portMapping.containerPort)/\(portMapping.transportProtocol)"
                arguments.append(contentsOf: ["-p", mapping])
            }
        }

        // Add volume mappings
        for volumeMapping in config.volumeMappings {
            if !volumeMapping.hostPath.isEmpty && !volumeMapping.containerPath.isEmpty {
                let mapping = volumeMapping.readonly
                    ? "\(volumeMapping.hostPath):\(volumeMapping.containerPath):ro"
                    : "\(volumeMapping.hostPath):\(volumeMapping.containerPath)"
                arguments.append(contentsOf: ["-v", mapping])
            }
        }

        // Add working directory
        if !config.workingDirectory.isEmpty {
            arguments.append(contentsOf: ["-w", config.workingDirectory])
        }

        // Add image name
        arguments.append(config.image)

        // Add command override if specified
        if !config.commandOverride.isEmpty {
            let commandArgs = config.commandOverride.split(separator: " ").map(String.init)
            arguments.append(contentsOf: commandArgs)
        }

        do {
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: arguments)

            await MainActor.run {
                if !result.failed {
                    let containerName = config.name.isEmpty ? "Container" : config.name
                    self.successMessage = "Successfully started container: \(containerName)"

                    // Refresh containers list
                    Task {
                        await loadContainers()
                    }
                } else {
                    let errorMsg = result.stderr ?? "Unknown error"
                    self.errorMessage = "Failed to run container: \(errorMsg)"
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to run container: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sudo Helper

    private func execWithSudo(program: String, arguments: [String]) throws -> ExecResult {
        // Create the command string
        let fullCommand = "\(program) \(arguments.joined(separator: " "))"

        // Use osascript to prompt for password and execute with sudo
        let script = """
        do shell script "\(fullCommand)" with administrator privileges
        """

        let result = try exec(
            program: "/usr/bin/osascript",
            arguments: ["-e", script])

        return result
    }
}

// MARK: - Type aliases for JSON decoding
typealias Containers = [Container]
typealias Images = [ContainerImage]
typealias Builders = [Builder]
