import Foundation
import SwiftExec
import SwiftUI

class ContainerService: ObservableObject {
    @Published var containers: [Container] = []
    @Published var images: [ContainerImage] = []
    @Published var builders: [Builder] = []
    @Published var registries: [Registry] = []
    @Published var isLoading: Bool = false
    @Published var isImagesLoading: Bool = false
    @Published var isBuildersLoading: Bool = false
    @Published var isRegistriesLoading: Bool = false
    @Published var errorMessage: String?
    @Published var systemStatus: SystemStatus = .unknown
    @Published var isSystemLoading = false
    @Published var loadingContainers: Set<String> = []
    @Published var isBuilderLoading = false
    @Published var builderStatus: BuilderStatus = .stopped
    @Published var defaultRegistry: String?
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

    private let defaultBinaryPath = "/usr/local/bin/container"
    private let customBinaryPathKey = "OrchardCustomBinaryPath"
    private let refreshIntervalKey = "OrchardRefreshInterval"
    private let lastUpdateCheckKey = "OrchardLastUpdateCheck"

    // App version info
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.5"
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

    var currentDefaultDomain: String? {
        return dnsDomains.first { $0.isDefault }?.domain
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

        var color: Color {
            switch self {
            case .unknown, .stopped:
                return .gray
            case .running:
                return .green
            }
        }

        var text: String {
            switch self {
            case .unknown:
                return "Unknown"
            case .stopped:
                return "Stopped"
            case .running:
                return "Running"
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
                arguments: ["images", "list", "--format", "json"])
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
                arguments: ["builder", "status", "--json"])
        } catch {
            let error = error as! ExecError
            result = error.execResult
        }

        do {
            let data = result.stdout?.data(using: .utf8)

            // Try to decode as single builder first
            if let data = data {
                do {
                    let newBuilder = try JSONDecoder().decode(Builder.self, from: data)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.builders = [newBuilder]
                        }
                        // Update status without animation to prevent flicker
                        self.builderStatus = newBuilder.status.lowercased() == "running" ? .running : .stopped
                        self.isBuildersLoading = false
                    }
                    print("Builder: \(newBuilder.configuration.id), Status: \(newBuilder.status)")
                    return
                } catch {
                    // If single builder decode fails, try array
                    do {
                        let newBuilders = try JSONDecoder().decode([Builder].self, from: data)
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.builders = newBuilders
                            }
                            // Update status without animation to prevent flicker
                            if let firstBuilder = newBuilders.first {
                                self.builderStatus = firstBuilder.status.lowercased() == "running" ? .running : .stopped
                            } else {
                                self.builderStatus = .stopped
                            }
                            self.isBuildersLoading = false
                        }
                        for builder in newBuilders {
                            print("Builder: \(builder.configuration.id), Status: \(builder.status)")
                        }
                        return
                    } catch {
                        print("Failed to decode builders as array: \(error)")
                    }
                }
            }

            // If we get here, decoding failed
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            print("No builder data or failed to decode")
        } catch {
            await MainActor.run {
                // If no builder exists, set empty array
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            print("No builder found or error loading builder: \(error)")
        }
    }

    func loadRegistries() async {
        await loadRegistries(showLoading: false)
    }

    func loadRegistries(showLoading: Bool = true) async {
        if showLoading {
            await MainActor.run {
                isRegistriesLoading = true
                errorMessage = nil
            }
        }

        do {
            // Get default registry
            let defaultResult = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["registry", "default", "inspect"])

            let defaultRegistry = defaultResult.stdout?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Create a registry list with the default registry
            var registryList: [Registry] = []

            if let defaultReg = defaultRegistry, !defaultReg.isEmpty {
                registryList.append(Registry(server: defaultReg, isDefault: true))
            }

            // Add common registries that might not be default
            let commonRegistries = ["docker.io", "ghcr.io", "quay.io", "registry.gitlab.com"]
            for registry in commonRegistries {
                if !registryList.contains(where: { $0.server == registry }) {
                    registryList.append(Registry(server: registry))
                }
            }

            await MainActor.run {
                self.registries = registryList
                self.defaultRegistry = defaultRegistry
                if showLoading {
                    self.isRegistriesLoading = false
                }
            }
        } catch {
            await MainActor.run {
                if showLoading {
                    self.errorMessage = "Failed to load registries: \(error.localizedDescription)"
                    self.isRegistriesLoading = false
                }
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
        var result: ExecResult
        do {
            result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["ls"])

            await MainActor.run {
                // Assuming the command returns success when running
                self.systemStatus = .running
            }
        } catch {
            await MainActor.run {
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
            }
        }

        do {
            // Get list of domains
            let listResult = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "dns", "ls"])

            // Get default domain
            let defaultResult = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "dns", "default", "inspect"])

            if let output = listResult.stdout {
                let defaultDomain = defaultResult.stdout?.trimmingCharacters(in: .whitespacesAndNewlines)
                let domains = parseDNSDomains(output, defaultDomain: defaultDomain)
                await MainActor.run {
                    self.dnsDomains = domains
                    if showLoading {
                        self.isDNSLoading = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                if showLoading {
                    self.errorMessage = "Failed to load DNS domains: \(error.localizedDescription)"
                    self.isDNSLoading = false
                }
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
            // Check if the domain being deleted is the default
            let isDefaultDomain = dnsDomains.first { $0.domain == domain }?.isDefault ?? false

            // If it's the default domain, unset it first
            if isDefaultDomain {
                let unsetResult = try exec(
                    program: safeContainerBinaryPath(),
                    arguments: ["system", "dns", "default", "unset"])

                if unsetResult.failed {
                    await MainActor.run {
                        self.errorMessage = unsetResult.stderr ?? "Failed to unset default DNS domain before deletion"
                    }
                    return
                }
            }

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

    func setDefaultDNSDomain(_ domain: String) async {
        await MainActor.run {
            isDNSLoading = true
        }

        do {
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "dns", "default", "set", domain])

            if !result.failed {
                await loadDNSDomains()
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to set default DNS domain"
                    self.isDNSLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to set default DNS domain: \(error.localizedDescription)"
                self.isDNSLoading = false
            }
        }
    }

    func unsetDefaultDNSDomain() async {
        await MainActor.run {
            isDNSLoading = true
        }

        do {
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["system", "dns", "default", "unset"])

            if !result.failed {
                await loadDNSDomains()
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to unset default DNS domain"
                    self.isDNSLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to unset default DNS domain: \(error.localizedDescription)"
                self.isDNSLoading = false
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

    // MARK: - Registry Management

    func loginToRegistry(_ request: RegistryLoginRequest) async {
        await MainActor.run {
            isRegistriesLoading = true
        }

        do {
            var arguments = ["registry", "login", "--username", request.username, request.server]

            if request.scheme != .auto {
                arguments.insert(contentsOf: ["--scheme", request.scheme.rawValue], at: 2)
            }

            // Create a process to handle password input
            let process = Process()
            process.executableURL = URL(fileURLWithPath: safeContainerBinaryPath())
            process.arguments = arguments + ["--password-stdin"]

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            // Send password through stdin
            inputPipe.fileHandleForWriting.write(request.password.data(using: .utf8) ?? Data())
            inputPipe.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            if process.terminationStatus == 0 {
                await loadRegistries()
                await MainActor.run {
                    self.successMessage = "Successfully logged into \(request.server)"
                }
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Login failed"
                await MainActor.run {
                    self.errorMessage = errorMessage
                    self.isRegistriesLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to login to registry: \(error.localizedDescription)"
                self.isRegistriesLoading = false
            }
        }
    }

    func logoutFromRegistry(_ server: String) async {
        await MainActor.run {
            isRegistriesLoading = true
        }

        do {
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["registry", "logout", server])

            if !result.failed {
                await loadRegistries()
                await MainActor.run {
                    self.successMessage = "Successfully logged out from \(server)"
                }
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to logout from registry"
                    self.isRegistriesLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to logout from registry: \(error.localizedDescription)"
                self.isRegistriesLoading = false
            }
        }
    }

    func setDefaultRegistry(_ server: String) async {
        await MainActor.run {
            isRegistriesLoading = true
        }

        do {
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["registry", "default", "set", server])

            if !result.failed {
                await loadRegistries()
                await MainActor.run {
                    self.successMessage = "Set \(server) as default registry"
                }
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to set default registry"
                    self.isRegistriesLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to set default registry: \(error.localizedDescription)"
                self.isRegistriesLoading = false
            }
        }
    }

    func unsetDefaultRegistry() async {
        await MainActor.run {
            isRegistriesLoading = true
        }

        do {
            let result = try exec(
                program: safeContainerBinaryPath(),
                arguments: ["registry", "default", "unset"])

            if !result.failed {
                await loadRegistries()
                await MainActor.run {
                    self.successMessage = "Unset default registry"
                }
            } else {
                await MainActor.run {
                    self.errorMessage = result.stderr ?? "Failed to unset default registry"
                    self.isRegistriesLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to unset default registry: \(error.localizedDescription)"
                self.isRegistriesLoading = false
            }
        }
    }

    private func parseDNSDomains(_ output: String, defaultDomain: String?) -> [DNSDomain] {
        let lines = output.components(separatedBy: .newlines)
        var domains: [DNSDomain] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.starts(with: "DOMAIN") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if let domain = components.first {
                    let isDefault = domain == defaultDomain
                    domains.append(DNSDomain(domain: domain, isDefault: isDefault))
                }
            }
        }

        return domains
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
