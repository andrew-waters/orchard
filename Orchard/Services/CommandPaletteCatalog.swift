import Foundation

/// Where an entry sits in the palette. Sections are the display grouping and the
/// tie-break order when scores are equal: actions, then navigation, then entities in
/// sidebar order.
enum PaletteSection: Int, CaseIterable {
    case actions
    case navigation
    case containers
    case images
    case mounts
    case machines
    case clusters
    case models
    case sandboxes
    case dns
    case networks

    var title: String {
        switch self {
        case .actions: return "Actions"
        case .navigation: return "Go to"
        case .containers: return TabSelection.containers.title
        case .images: return TabSelection.images.title
        case .mounts: return TabSelection.mounts.title
        case .machines: return TabSelection.machines.title
        case .clusters: return TabSelection.clusters.title
        case .models: return TabSelection.models.title
        case .sandboxes: return TabSelection.sandboxes.title
        case .dns: return TabSelection.dns.title
        case .networks: return TabSelection.networks.title
        }
    }
}

/// The typed intent an entry fires. The palette view hands these back to `ContentView`,
/// which owns the selection state and services - the catalog stays pure data.
/// Destructive operations (delete, kill, prune) are deliberately not palette-reachable.
enum PaletteAction: Equatable {
    case navigate(TabSelection)

    case selectContainer(String)
    case selectImage(String)
    case selectMount(String)
    case selectMachine(String)
    case selectCluster(String)
    case selectModel(String)
    case selectSandbox(String)
    case selectDNSDomain(String)
    case selectNetwork(String)

    case showRunContainerSheet
    case showImageSearch
    case showAddDNSDomainSheet
    case showAddNetworkSheet
    case showAddMachineSheet
    case showCreateClusterSheet

    case startSystem
    case stopSystem
    case restartSystem
    case refreshAll
    case startBuilder
    case stopBuilder
    case setRecommendedKernel
    case checkForUpdates

    case startContainer(String)
    case stopContainer(String)
    case openContainerLogs(String)
    case openContainerTerminal(String)
    case bootMachine(String)
    case stopMachine(String)
    case openMachineLogs(String)
}

struct PaletteEntry: Identifiable, Equatable {
    let id: String
    let section: PaletteSection
    let icon: String
    let title: String
    let subtitle: String?
    /// Hidden search terms (verb synonyms, statuses, hostnames) scored at a discount so
    /// title matches always rank above keyword-only matches.
    let keywords: String
    /// Whether the entry appears in the curated empty-query list. Verb entries and the
    /// noisier catalogs (mounts, obscure actions) surface only once the user types.
    let showsWhenEmpty: Bool
    let action: PaletteAction

    init(
        id: String,
        section: PaletteSection,
        icon: String,
        title: String,
        subtitle: String? = nil,
        keywords: String = "",
        showsWhenEmpty: Bool = true,
        action: PaletteAction
    ) {
        self.id = id
        self.section = section
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.showsWhenEmpty = showsWhenEmpty
        self.action = action
    }
}

/// Builds the palette's entry catalog from a snapshot of service state and ranks it
/// against a query. Both functions are pure: the snapshot is taken when the palette
/// opens, so the 5s background refresh never reshuffles results under the cursor.
enum CommandPaletteCatalog {

    // MARK: Catalog

    static func entries(
        containers: [Container],
        images: [ContainerImage],
        mounts: [ContainerMount],
        machines: [Machine],
        clusters: [K8sCluster],
        providers: [ModelProvider],
        sandboxes: [Sandbox],
        dnsDomains: [DNSDomain],
        networks: [ContainerNetwork],
        systemRunning: Bool
    ) -> [PaletteEntry] {
        var entries: [PaletteEntry] = []

        entries.append(contentsOf: actionEntries(systemRunning: systemRunning))
        entries.append(contentsOf: navigationEntries())

        // Running containers before stopped, alphabetical within each group - this is
        // also the curated empty-query order.
        let ordered = containers.sorted {
            let (a, b) = ($0.configuration.id, $1.configuration.id)
            let (ra, rb) = ($0.status == "running", $1.status == "running")
            return ra == rb ? a < b : ra
        }
        for container in ordered {
            entries.append(contentsOf: containerEntries(container))
        }

        for image in images.sorted(by: { $0.reference < $1.reference }) {
            entries.append(PaletteEntry(
                id: "image:\(image.reference)",
                section: .images,
                icon: TabSelection.images.icon,
                title: image.reference,
                keywords: "image",
                action: .selectImage(image.reference)))
        }

        for mount in mounts.sorted(by: { $0.id < $1.id }) {
            entries.append(PaletteEntry(
                id: "mount:\(mount.id)",
                section: .mounts,
                icon: TabSelection.mounts.icon,
                title: mount.id,
                subtitle: mount.mountType,
                keywords: "mount volume",
                showsWhenEmpty: false,
                action: .selectMount(mount.id)))
        }

        for machine in machines.sorted(by: { $0.id < $1.id }) {
            entries.append(contentsOf: machineEntries(machine))
        }

        for cluster in clusters.sorted(by: { $0.name < $1.name }) {
            entries.append(PaletteEntry(
                id: "cluster:\(cluster.name)",
                section: .clusters,
                icon: TabSelection.clusters.icon,
                title: cluster.name,
                subtitle: "\(cluster.status) · \(cluster.nodes.count) node\(cluster.nodes.count == 1 ? "" : "s")",
                keywords: "cluster kubernetes k8s",
                action: .selectCluster(cluster.name)))
        }

        for provider in providers.sorted(by: { $0.port < $1.port }) {
            entries.append(PaletteEntry(
                id: "model:\(provider.id)",
                section: .models,
                icon: TabSelection.models.icon,
                title: "\(provider.kind.displayName) · port \(provider.port)",
                subtitle: provider.models.first,
                keywords: "model ai llm \(provider.models.joined(separator: " "))",
                action: .selectModel(provider.id)))
        }

        for sandbox in sandboxes.sorted(by: { $0.name < $1.name }) {
            entries.append(PaletteEntry(
                id: "sandbox:\(sandbox.id)",
                section: .sandboxes,
                icon: TabSelection.sandboxes.icon,
                title: sandbox.name,
                keywords: "sandbox agent",
                action: .selectSandbox(sandbox.id)))
        }

        for domain in dnsDomains.sorted(by: { $0.domain < $1.domain }) {
            entries.append(PaletteEntry(
                id: "dns:\(domain.domain)",
                section: .dns,
                icon: TabSelection.dns.icon,
                title: domain.domain,
                subtitle: domain.isDefault ? "default domain" : nil,
                keywords: "dns domain",
                action: .selectDNSDomain(domain.domain)))
        }

        for network in networks.sorted(by: { $0.id < $1.id }) {
            entries.append(PaletteEntry(
                id: "network:\(network.id)",
                section: .networks,
                icon: TabSelection.networks.icon,
                title: network.id,
                subtitle: network.state,
                keywords: "network subnet",
                action: .selectNetwork(network.id)))
        }

        return entries
    }

    // MARK: Ranking

    /// Empty query: the curated list in catalog order. Otherwise: fuzzy-score titles at
    /// full weight and keywords/subtitles at a discount, drop non-matches, sort by score,
    /// breaking ties by section order then catalog order.
    static func rank(_ entries: [PaletteEntry], query: String) -> [PaletteEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return entries.filter(\.showsWhenEmpty)
        }
        let scored: [(entry: PaletteEntry, score: Int, index: Int)] = entries.enumerated().compactMap { index, entry in
            var best: Int? = FuzzyMatch.score(query: trimmed, candidate: entry.title)
            if let keywordScore = FuzzyMatch.score(query: trimmed, candidate: entry.keywords) {
                best = max(best ?? Int.min, keywordScore - 15)
            }
            if let subtitle = entry.subtitle, let subtitleScore = FuzzyMatch.score(query: trimmed, candidate: subtitle) {
                best = max(best ?? Int.min, subtitleScore - 10)
            }
            guard let score = best else { return nil }
            return (entry, score, index)
        }
        let ranked = scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.entry.section != $1.entry.section {
                return $0.entry.section.rawValue < $1.entry.section.rawValue
            }
            return $0.index < $1.index
        }
        // Regroup into contiguous sections so headers never repeat: sections appear in
        // order of their best-scoring entry, entries keep score order within a section.
        var sectionOrder: [PaletteSection] = []
        for item in ranked where !sectionOrder.contains(item.entry.section) {
            sectionOrder.append(item.entry.section)
        }
        return sectionOrder.flatMap { section in
            ranked.lazy.filter { $0.entry.section == section }.map(\.entry)
        }
    }

    // MARK: Sections

    private static func actionEntries(systemRunning: Bool) -> [PaletteEntry] {
        var actions: [PaletteEntry] = [
            PaletteEntry(
                id: "action:runContainer",
                section: .actions,
                icon: "play.circle",
                title: "Run a Container...",
                subtitle: "Create and start from an image",
                keywords: "run create new container start",
                action: .showRunContainerSheet),
            PaletteEntry(
                id: "action:pullImage",
                section: .actions,
                icon: "arrow.down.circle",
                title: "Pull an Image...",
                subtitle: "Search Docker Hub or pull by reference",
                keywords: "pull download image docker hub registry search explore",
                action: .showImageSearch),
            PaletteEntry(
                id: "action:addDNS",
                section: .actions,
                icon: TabSelection.dns.icon,
                title: "Add DNS Domain...",
                keywords: "dns domain create add local",
                action: .showAddDNSDomainSheet),
            PaletteEntry(
                id: "action:addNetwork",
                section: .actions,
                icon: TabSelection.networks.icon,
                title: "Add Network...",
                keywords: "network create add subnet",
                action: .showAddNetworkSheet),
            PaletteEntry(
                id: "action:createMachine",
                section: .actions,
                icon: TabSelection.machines.icon,
                title: "Create Machine...",
                keywords: "machine vm create new linux",
                action: .showAddMachineSheet),
            PaletteEntry(
                id: "action:createCluster",
                section: .actions,
                icon: TabSelection.clusters.icon,
                title: "Create Cluster...",
                keywords: "kubernetes k8s cluster create new",
                action: .showCreateClusterSheet),
        ]

        if systemRunning {
            actions.append(PaletteEntry(
                id: "action:stopSystem",
                section: .actions,
                icon: "power",
                title: "Stop the Container System",
                keywords: "daemon service shutdown stop apiserver",
                action: .stopSystem))
            actions.append(PaletteEntry(
                id: "action:restartSystem",
                section: .actions,
                icon: "arrow.clockwise.circle",
                title: "Restart the Container System",
                keywords: "daemon service restart reboot apiserver",
                action: .restartSystem))
        } else {
            actions.append(PaletteEntry(
                id: "action:startSystem",
                section: .actions,
                icon: "power",
                title: "Start the Container System",
                keywords: "daemon service boot start apiserver",
                action: .startSystem))
        }

        actions.append(PaletteEntry(
            id: "action:refresh",
            section: .actions,
            icon: "arrow.clockwise",
            title: "Refresh",
            keywords: "reload refresh sync",
            action: .refreshAll))

        actions.append(contentsOf: [
            PaletteEntry(
                id: "action:startBuilder",
                section: .actions,
                icon: "hammer",
                title: "Start the Builder",
                keywords: "builder buildkit start",
                showsWhenEmpty: false,
                action: .startBuilder),
            PaletteEntry(
                id: "action:stopBuilder",
                section: .actions,
                icon: "hammer",
                title: "Stop the Builder",
                keywords: "builder buildkit stop",
                showsWhenEmpty: false,
                action: .stopBuilder),
            PaletteEntry(
                id: "action:recommendedKernel",
                section: .actions,
                icon: "memorychip",
                title: "Use the Recommended Kernel",
                keywords: "kernel recommended set install",
                showsWhenEmpty: false,
                action: .setRecommendedKernel),
            PaletteEntry(
                id: "action:checkUpdates",
                section: .actions,
                icon: "arrow.down.app",
                title: "Check for Updates...",
                keywords: "update upgrade version new release",
                showsWhenEmpty: false,
                action: .checkForUpdates),
        ])

        return actions
    }

    private static func navigationEntries() -> [PaletteEntry] {
        TabSelection.allCases.map { tab in
            PaletteEntry(
                id: "nav:\(tab.rawValue)",
                section: .navigation,
                icon: tab.icon,
                title: "Go to \(tab.title)",
                keywords: "\(tab.rawValue) open show view section tab",
                action: .navigate(tab))
        }
    }

    private static func containerEntries(_ container: Container) -> [PaletteEntry] {
        let id = container.configuration.id
        let running = container.status == "running"
        var entries: [PaletteEntry] = [
            PaletteEntry(
                id: "container:\(id)",
                section: .containers,
                icon: TabSelection.containers.icon,
                title: id,
                subtitle: "\(container.configuration.image.reference) · \(container.status)",
                keywords: "container \(container.status) \(container.configuration.hostname ?? "")",
                action: .selectContainer(id)),
        ]
        if running {
            entries.append(PaletteEntry(
                id: "container:\(id):stop",
                section: .containers,
                icon: "stop.circle",
                title: "Stop: \(id)",
                keywords: "stop halt container \(id)",
                showsWhenEmpty: false,
                action: .stopContainer(id)))
            entries.append(PaletteEntry(
                id: "container:\(id):console",
                section: .containers,
                icon: "terminal",
                title: "Console: \(id)",
                subtitle: "Open a shell in your terminal",
                keywords: "console shell terminal exec attach \(id)",
                showsWhenEmpty: false,
                action: .openContainerTerminal(id)))
        } else {
            entries.append(PaletteEntry(
                id: "container:\(id):start",
                section: .containers,
                icon: "play.circle",
                title: "Start: \(id)",
                keywords: "start run boot container \(id)",
                showsWhenEmpty: false,
                action: .startContainer(id)))
        }
        entries.append(PaletteEntry(
            id: "container:\(id):logs",
            section: .containers,
            icon: "doc.plaintext",
            title: "Logs: \(id)",
            subtitle: "Open in the log viewer",
            keywords: "logs tail follow output \(id)",
            showsWhenEmpty: false,
            action: .openContainerLogs(id)))
        return entries
    }

    private static func machineEntries(_ machine: Machine) -> [PaletteEntry] {
        var entries: [PaletteEntry] = [
            PaletteEntry(
                id: "machine:\(machine.id)",
                section: .machines,
                icon: TabSelection.machines.icon,
                title: machine.id,
                subtitle: "\(machine.status) · \(machine.imageReference)",
                keywords: "machine vm \(machine.status)",
                action: .selectMachine(machine.id)),
        ]
        if machine.isRunning {
            entries.append(PaletteEntry(
                id: "machine:\(machine.id):stop",
                section: .machines,
                icon: "stop.circle",
                title: "Stop: \(machine.id)",
                keywords: "stop halt machine vm \(machine.id)",
                showsWhenEmpty: false,
                action: .stopMachine(machine.id)))
        } else {
            entries.append(PaletteEntry(
                id: "machine:\(machine.id):boot",
                section: .machines,
                icon: "play.circle",
                title: "Boot: \(machine.id)",
                keywords: "boot start machine vm \(machine.id)",
                showsWhenEmpty: false,
                action: .bootMachine(machine.id)))
        }
        entries.append(PaletteEntry(
            id: "machine:\(machine.id):logs",
            section: .machines,
            icon: "doc.plaintext",
            title: "Logs: \(machine.id)",
            subtitle: "Open in the log viewer",
            keywords: "logs tail machine vm \(machine.id)",
            showsWhenEmpty: false,
            action: .openMachineLogs(machine.id)))
        return entries
    }
}
