import Foundation
import Combine

/// App version, read once from the bundle. (Previously `ContainerService.currentVersion`.)
enum AppInfo {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
}

/// Constructs and wires the per-domain services and owns their lifetime. Not a facade —
/// views observe the individual services directly; this only holds them and the
/// cross-service callbacks that were previously set up in `ContainerService.init`.
@MainActor
final class AppServices: ObservableObject {
    let alertCenter: AlertCenter
    let settings: SettingsStore
    let terminalLauncher: TerminalLauncher
    let builderService: BuilderService
    let networkService: NetworkService
    let imageService: ImageService
    let statsService: StatsService
    let dnsService: DNSService
    let systemService: SystemService
    let containerListService: ContainerListService

    /// The services for app launch: normally the live backend, or (Debug + launch arg) an
    /// in-memory stub seeded with fixtures for the XCUITest smoke suite.
    static func forLaunch() -> AppServices {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(uiTestMockBackendArgument) {
            return AppServices(backend: UITestBackend(), runner: UITestCommandRunner())
        }
        #endif
        let services = AppServices()
        // Start always-on stats sampling + restore persisted history (real launch only).
        services.statsService.activate()
        return services
    }

    init(
        backend: ContainerBackend = LiveContainerBackend(),
        runner: CommandRunner = SystemCommandRunner(),
        defaults: UserDefaults = .standard
    ) {
        let alertCenter = AlertCenter()
        self.alertCenter = alertCenter
        let settings = SettingsStore(alertCenter: alertCenter, defaults: defaults)
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

        containerListService.reloadBuilders = { [weak builderService] in await builderService?.loadBuilders() }
        // DNS ↔ System: the default domain is a system property.
        dnsService.refreshSystemProperties = { [weak systemService] in await systemService?.loadSystemProperties(showLoading: false) }
        dnsService.defaultDomain = { [weak systemService] in
            systemService?.systemProperties.first(where: { $0.id == "dns.domain" })?.value
        }
        dnsService.setDefaultDomainProperty = { [weak systemService] domain in
            systemService?.setDNSDomainPropertyOptimistically(domain)
        }
        // System → containers/DNS side effects.
        systemService.onSystemStarted = { [weak containerListService] in await containerListService?.loadContainers() }
        systemService.onSystemStopped = { [weak containerListService] in containerListService?.containers.removeAll() }
        systemService.markDNSDefault = { [weak dnsService] domain in dnsService?.markDefault(domain) }
        systemService.reloadDNS = { [weak dnsService] in await dnsService?.load(showLoading: false) }
    }
}
