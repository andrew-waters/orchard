import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
class ContainerService: ObservableObject {
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
    /// Container list and lifecycle.
    let containerListService: ContainerListService
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
        let dnsService = DNSService(runner: runner, settings: settings, alertCenter: alertCenter)
        self.dnsService = dnsService
        let systemService = SystemService(backend: backend, runner: runner, settings: settings, alertCenter: alertCenter)
        self.systemService = systemService
        // ContainerListService is built before StatsService, which depends on it.
        let containerListService = ContainerListService(backend: backend, alertCenter: alertCenter)
        self.containerListService = containerListService
        let statsService = StatsService(backend: backend, alertCenter: alertCenter, containerList: containerListService)
        self.statsService = statsService

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
            containerListService.objectWillChange,
        ] {
            store.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        containerListService.reloadBuilders = { [weak self] in await self?.builderService.loadBuilders() }
        // DNS ↔ System: the default domain is a system property.
        dnsService.refreshSystemProperties = { [weak self] in await self?.systemService.loadSystemProperties(showLoading: false) }
        dnsService.defaultDomain = { [weak self] in
            self?.systemService.systemProperties.first(where: { $0.id == "dns.domain" })?.value
        }
        dnsService.setDefaultDomainProperty = { [weak self] domain in
            self?.systemService.setDNSDomainPropertyOptimistically(domain)
        }
        // System → containers/DNS side effects.
        systemService.onSystemStarted = { [weak self] in await self?.containerListService.loadContainers() }
        systemService.onSystemStopped = { [weak self] in self?.containerListService.containers.removeAll() }
        systemService.markDNSDefault = { [weak self] domain in self?.dnsService.markDefault(domain) }
        systemService.reloadDNS = { [weak self] in await self?.dnsService.load(showLoading: false) }
    }

    // MARK: - Settings (forwarded to SettingsStore)

    var containerBinaryPath: String { settings.containerBinaryPath }
    var isUsingCustomBinary: Bool { settings.isUsingCustomBinary }
    var preferredTerminal: TerminalApp { settings.preferredTerminal }
    var installedTerminals: [TerminalApp] { settings.installedTerminals }

    func setCustomBinaryPath(_ path: String?) { settings.setCustomBinaryPath(path) }
    func resetToDefaultBinary() { settings.resetToDefaultBinary() }
    func validateAndSetCustomBinaryPath(_ path: String?) -> Bool { settings.validateAndSetCustomBinaryPath(path) }
    func setPreferredTerminal(_ terminal: TerminalApp) { settings.setPreferredTerminal(terminal) }

    // MARK: - Container list (forwarded to ContainerListService)

    var containers: [Container] { containerListService.containers }
    var loadingContainers: Set<String> { containerListService.loadingContainers }
    var isLoading: Bool { containerListService.isLoading }
    var allMounts: [ContainerMount] { containerListService.allMounts }
    var recoveryFailedContainerIDs: Set<String> { containerListService.recoveryFailedContainerIDs }

    func loadContainers(showLoading: Bool = true) async { await containerListService.loadContainers(showLoading: showLoading) }
    func forceStopContainer(_ id: String) async { await containerListService.forceStopContainer(id) }
    func stopContainer(_ id: String) async { await containerListService.stopContainer(id) }
    func startContainer(_ id: String, maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) async {
        await containerListService.startContainer(id, maxRetries: maxRetries, retryDelay: retryDelay)
    }
    func removeContainer(_ id: String) async { await containerListService.removeContainer(id) }
    func removeContainers(_ ids: [String]) async { await containerListService.removeContainers(ids) }
    func fetchContainerLogs(containerId: String, tailLines: Int = 5000) async throws -> [String] {
        try await containerListService.fetchContainerLogs(containerId: containerId, tailLines: tailLines)
    }
    func recreateContainer(oldContainerId: String, newConfig: ContainerRunConfig) async {
        await containerListService.recreateContainer(oldContainerId: oldContainerId, newConfig: newConfig)
    }
    @discardableResult
    func runContainer(config: ContainerRunConfig) async -> Bool { await containerListService.runContainer(config: config) }

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
    var isBuildersLoading: Bool { builderService.isBuildersLoading }

    func loadBuilders() async { await builderService.loadBuilders() }


    // MARK: - Container Stats (forwarded to StatsService)

    var containerStats: [ContainerStats] { statsService.containerStats }
    var isStatsLoading: Bool { statsService.isStatsLoading }
    var statsUnavailable: Bool { statsService.statsUnavailable }

    func loadContainerStats(showLoading: Bool = true) async { await statsService.load(showLoading: showLoading) }

    // MARK: - System (forwarded to SystemService)

    var systemStatus: SystemStatus { systemService.systemStatus }
    var systemStatusError: String? { systemService.systemStatusError }
    var isSystemLoading: Bool { systemService.isSystemLoading }
    var containerVersion: String? { systemService.containerVersion }
    var parsedContainerVersion: String? { systemService.parsedContainerVersion }
    var isKernelLoading: Bool { systemService.isKernelLoading }
    var systemProperties: [SystemProperty] { systemService.systemProperties }
    var isSystemPropertiesLoading: Bool { systemService.isSystemPropertiesLoading }
    var systemDiskUsage: SystemDiskUsage? { systemService.systemDiskUsage }
    var isSystemDiskUsageLoading: Bool { systemService.isSystemDiskUsageLoading }

    func checkSystemStatus() async { await systemService.checkSystemStatus() }
    func checkSystemStatusIgnoreVersion() async { await systemService.checkSystemStatusIgnoreVersion() }
    func startSystem() async { await systemService.startSystem() }
    func stopSystem() async { await systemService.stopSystem() }
    func restartSystem() async { await systemService.restartSystem() }
    func loadSystemProperties(showLoading: Bool = true) async { await systemService.loadSystemProperties(showLoading: showLoading) }
    func setSystemProperty(_ id: String, value: String) async { await systemService.setSystemProperty(id, value: value) }
    func loadSystemDiskUsage(showLoading: Bool = true) async { await systemService.loadSystemDiskUsage(showLoading: showLoading) }




    // MARK: - DNS (forwarded to DNSService)

    var dnsDomains: [DNSDomain] { dnsService.dnsDomains }
    var isDNSLoading: Bool { dnsService.isDNSLoading }

    func loadDNSDomains(showLoading: Bool = true) async { await dnsService.load(showLoading: showLoading) }
    @discardableResult
    func createDNSDomain(_ domain: String) async -> Bool { await dnsService.create(domain) }
    func deleteDNSDomain(_ domain: String) async { await dnsService.delete(domain) }
    func setDefaultDNSDomain(_ domain: String) async { await dnsService.setDefault(domain) }

    // MARK: - Networks (forwarded to NetworkService)

    var networks: [ContainerNetwork] { networkService.networks }
    var isNetworksLoading: Bool { networkService.isNetworksLoading }

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


}

