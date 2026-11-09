import Foundation

// MARK: - Cluster model

/// A node container in a local Kubernetes cluster, as created by Apple container's cluster
/// plugin (`container cluster`, `container k8s` before 1.6.1). Wraps the container snapshot
/// with the cluster it belongs to.
struct K8sClusterNode: Identifiable, Equatable {
    let clusterName: String
    let container: Container

    var id: String { container.configuration.id }
    var role: String? { container.pluginRole }
    /// Membership, not equality: a single-node cluster's node is `control-plane,worker`.
    var isControlPlane: Bool { container.pluginRoles.contains(K8sCluster.controlPlaneRole) }
    var isRunning: Bool { container.status.lowercased() == "running" }
    var address: String? { container.networks.first?.address }
}

/// A local Kubernetes cluster: the cluster-plugin-owned node containers grouped by cluster.
/// The cluster's name is its control-plane container's id; workers are named
/// `<cluster>-worker-N`. Grouping mirrors `K8sHelper.buildK8sRows` in apple/container.
struct K8sCluster: Identifiable, Equatable {
    /// The plugin label on node containers: `cluster` from container 1.6.1
    /// (apple/container#2427), `k8s` before. Either is a cluster node, so a cluster made
    /// before an upgrade still shows.
    static let pluginName = "cluster"
    static let legacyPluginName = "k8s"
    static let pluginNames: Set<String> = [pluginName, legacyPluginName]
    static let controlPlaneRole = "control-plane"
    /// The most workers `create --workers` accepts (1.6.0).
    static let maxWorkers = 1024

    let name: String
    let nodes: [K8sClusterNode]
    /// What the clusters service stored for it (container 1.7). Nil for a cluster made before
    /// 1.7, below 1.7, or when `cluster ls` couldn't be read.
    var stored: StoredClusterConfiguration? = nil

    var id: String { name }
    var controlPlane: K8sClusterNode? { nodes.first(where: { $0.isControlPlane }) }
    var workers: [K8sClusterNode] { nodes.filter { !$0.isControlPlane } }
    /// A cluster is running when its control plane is; workers can lag behind.
    var isRunning: Bool { controlPlane?.isRunning ?? false }
    var status: String { controlPlane?.container.status ?? nodes.first?.container.status ?? "unknown" }
    /// Whether the cluster's nodes pull from the Mac's own image store, as a cluster made with
    /// `cluster create --shared-image-store` (container 1.7) does. Read off the control plane's
    /// mounts, so it holds for a cluster made outside Orchard too.
    var usesSharedImageStore: Bool {
        guard let node = controlPlane ?? nodes.first else { return false }
        return node.container.configuration.mounts.contains { $0.destination == Self.hostStoreSocketMountPath }
    }
    /// Where `--shared-image-store` mounts the host store's socket in each node
    /// (`ClusterHelper.nodeHostStoreSocketPath` upstream).
    static let hostStoreSocketMountPath = "/opt/cluster-shim/hoststore.sock"
    /// Made by the `k8s` plugin, before container 1.6.1. From 1.6.1 the CLI only sees nodes
    /// labelled `cluster`, so such a cluster can't be managed through it: see `ClusterService.isStranded`.
    var isLegacy: Bool { !nodes.isEmpty && nodes.allSatisfy { $0.container.owningPlugin == Self.legacyPluginName } }

    /// The cluster a k8s node container belongs to: a control plane names its own
    /// cluster; a worker derives it from `<cluster>-worker-N`, falling back to the id.
    /// Nil for containers the cluster plugin doesn't own.
    static func clusterName(for container: Container) -> String? {
        guard container.isK8sNode else { return nil }
        let id = container.configuration.id
        if container.pluginRoles.contains(controlPlaneRole) { return id }
        let derived = id.components(separatedBy: "-worker-").dropLast().joined(separator: "-worker-")
        return derived.isEmpty ? id : derived
    }

    /// Group the cluster plugin's node containers into clusters, under either label. Pure so
    /// it can be unit tested; containers not owned by the plugin are ignored.
    ///
    /// `stored` is what `container cluster ls` reports (container 1.7), attached to the cluster
    /// of the same name. Node state still comes from the containers. A stored cluster with no
    /// node containers left is listed with no nodes, as the CLI lists it, so it can be deleted.
    static func group(containers: [Container], stored: [String: StoredClusterConfiguration] = [:]) -> [K8sCluster] {
        var clusters = groupNodes(containers: containers)
        for index in clusters.indices {
            clusters[index].stored = stored[clusters[index].name]
        }
        let grouped = Set(clusters.map(\.name))
        for (name, configuration) in stored where !grouped.contains(name) {
            clusters.append(K8sCluster(name: name, nodes: [], stored: configuration))
        }
        return clusters.sorted { $0.name < $1.name }
    }

    private static func groupNodes(containers: [Container]) -> [K8sCluster] {
        let nodes = containers.filter(\.isK8sNode)
        var controlPlanes: [Container] = []
        var workers: [Container] = []
        for node in nodes {
            if node.pluginRoles.contains(controlPlaneRole) {
                controlPlanes.append(node)
            } else {
                workers.append(node)
            }
        }

        var clusters: [K8sCluster] = []
        var assignedWorkerIDs = Set<String>()

        for cp in controlPlanes.sorted(by: { $0.configuration.id < $1.configuration.id }) {
            let clusterName = cp.configuration.id
            let cpWorkers = workers
                .filter { $0.configuration.id.hasPrefix("\(clusterName)-worker-") }
                .sorted { $0.configuration.id < $1.configuration.id }
            cpWorkers.forEach { assignedWorkerIDs.insert($0.configuration.id) }
            clusters.append(K8sCluster(
                name: clusterName,
                nodes: ([cp] + cpWorkers).map { K8sClusterNode(clusterName: clusterName, container: $0) }))
        }

        // Workers whose control plane is gone still group under their derived cluster
        // name so they aren't orphaned rows (same fallback as upstream).
        let orphans = workers
            .filter { !assignedWorkerIDs.contains($0.configuration.id) }
            .sorted { $0.configuration.id < $1.configuration.id }
        var orphanClusters: [String: [Container]] = [:]
        for w in orphans {
            guard let clusterName = clusterName(for: w) else { continue }
            orphanClusters[clusterName, default: []].append(w)
        }
        for (clusterName, members) in orphanClusters.sorted(by: { $0.key < $1.key }) {
            clusters.append(K8sCluster(
                name: clusterName,
                nodes: members.map { K8sClusterNode(clusterName: clusterName, container: $0) }))
        }

        return clusters.sorted { $0.name < $1.name }
    }
}

// MARK: - Service

/// Whether the cluster plugin is usable on this install.
enum K8sPluginAvailability: Equatable {
    /// Not probed yet (or the probe failed for reasons other than a missing plugin,
    /// e.g. the system was stopped) — probe again next time.
    case unknown
    case available
    /// The container CLI reported the plugin missing: pre-1.2.2 install.
    case missingPlugin
}

/// The CNI a cluster is created with: `k8s create`'s default kindnet, a manifest applied in its
/// place (1.5.0), or none at all (`--cni NONE`, 1.6.0), which leaves the user to install one.
/// Not `none`, which would read as `Optional.none` wherever this is optional.
enum ClusterCNI: Equatable {
    case kindnet
    case manifest(String)
    case userInstalled

    /// The CNI a cluster's stored configuration records: the manifest path, `NONE` for no CNI,
    /// or null for kindnet (`ClusterConfiguration.cni` upstream).
    init(storedValue: String?) {
        guard let storedValue, !storedValue.isEmpty else { self = .kindnet; return }
        self = storedValue.uppercased() == "NONE" ? .userInstalled : .manifest(storedValue)
    }
}

/// Some of a cluster's workers, sized alike: one `--workers` value. Container 1.7 sizes worker
/// groups apart from the control plane (`--workers count=<n>,cpus=<n>,memory=<size>`,
/// apple/container#2448). A group with no size is a plain count, and on 1.7 its workers get
/// the single-node defaults (a quarter of the host, at least 2 CPUs and 2 GB). Below 1.7 every
/// worker matches the control plane and only the count is sent.
struct ClusterWorkerGroup: Codable, Equatable, Hashable {
    var count: Int
    var cpus: Int?
    var memoryGiB: Int?

    init(count: Int, cpus: Int? = nil, memoryGiB: Int? = nil) {
        self.count = count
        self.cpus = cpus
        self.memoryGiB = memoryGiB
    }

    var isSized: Bool { cpus != nil || memoryGiB != nil }

    /// What 1.7 gives a worker with no size: the single-node defaults, a quarter of the host's
    /// CPUs and memory with at least 2 CPUs and 2 GB. Starting values for the worker fields.
    static var defaultCPUs: Int { max(2, ProcessInfo.processInfo.processorCount / 4) }
    static var defaultMemoryGiB: Int { max(2, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) / 4) }

    /// "2 workers, 4 CPUs and 8 GB each", or "2 workers" for an unsized group.
    static func summary(of group: ClusterWorkerGroup) -> String {
        let count = group.count == 1 ? "1 worker" : "\(group.count) workers"
        guard group.isSized else { return count }
        let sizes = [group.cpus.map { $0 == 1 ? "1 CPU" : "\($0) CPUs" }, group.memoryGiB.map { "\($0) GB" }]
            .compactMap { $0 }.joined(separator: " and ")
        return "\(count), \(sizes) \(group.count == 1 ? "" : "each")".trimmingCharacters(in: .whitespaces)
    }

    /// The `--workers` value: a plain count, or `count=<n>,cpus=<n>,memory=<n>GB` with only
    /// the sizes that are set.
    var argument: String {
        guard isSized else { return String(count) }
        var parts = ["count=\(count)"]
        if let cpus { parts.append("cpus=\(cpus)") }
        if let memoryGiB { parts.append("memory=\(memoryGiB)GB") }
        return parts.joined(separator: ",")
    }

    /// The live workers grouped by size, in the order their sizes first appear. Workers sized
    /// alike are one group whatever order they were made in.
    static func groups(of workers: [K8sClusterNode]) -> [ClusterWorkerGroup] {
        var groups: [ClusterWorkerGroup] = []
        for worker in workers {
            let resources = worker.container.configuration.resources
            let cpus = resources.cpus
            let memoryGiB = max(1, resources.memoryInBytes / 1_073_741_824)
            if let index = groups.firstIndex(where: { $0.cpus == cpus && $0.memoryGiB == memoryGiB }) {
                groups[index].count += 1
            } else {
                groups.append(ClusterWorkerGroup(count: 1, cpus: cpus, memoryGiB: memoryGiB))
            }
        }
        return groups
    }
}

/// What the clusters service (`container-core-clusters`, container 1.7, apple/container#2451)
/// stored for a cluster when it was created, from `container cluster ls --format json`. Only
/// the fields Orchard uses, decoded leniently so a field upstream adds or reshapes can't cost
/// the rest. Clusters made before 1.7 have none.
struct StoredClusterConfiguration: Equatable {
    struct Node: Equatable {
        let name: String
        let roles: [String]
    }

    let name: String
    /// The node image's tag, such as `v1.35.5`.
    let kubernetesVersion: String
    /// The manifest path, `NONE`, or nil for kindnet.
    let cni: String?
    let sharedImageStore: Bool
    let nodes: [Node]
    let creationDate: Date?

    var clusterCNI: ClusterCNI { ClusterCNI(storedValue: cni) }
    /// Nodes that aren't the control plane. A single node carries both roles and isn't one.
    var workerCount: Int { nodes.filter { !$0.roles.contains(K8sCluster.controlPlaneRole) }.count }

    /// Parse `container cluster ls --format json`: an array of `{id, configuration, status}`.
    /// Entries that don't have a name and Kubernetes version are skipped; nil when the output
    /// isn't such an array at all, so a caller can keep what it had.
    static func parseList(json: String) -> [StoredClusterConfiguration]? {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return entries.compactMap { entry in
            guard let configuration = entry["configuration"] as? [String: Any],
                  let name = configuration["name"] as? String, !name.isEmpty,
                  let version = configuration["kubernetesVersion"] as? String
            else { return nil }
            let nodes = (configuration["nodes"] as? [[String: Any]] ?? []).compactMap { node -> Node? in
                guard let name = node["name"] as? String else { return nil }
                return Node(name: name, roles: node["roles"] as? [String] ?? [])
            }
            let creationDate = (configuration["creationDate"] as? String).flatMap(Self.parseDate)
            return StoredClusterConfiguration(
                name: name, kubernetesVersion: version, cni: configuration["cni"] as? String,
                sharedImageStore: configuration["sharedImageStore"] as? Bool ?? false,
                nodes: nodes, creationDate: creationDate)
        }
    }

    /// The CLI writes ISO 8601 dates, with or without fractional seconds. Upstream decodes a
    /// missing date as 1970, which says nothing, so that is treated as unknown too.
    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        var date = formatter.date(from: text)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatter.date(from: text)
        }
        guard let date, date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
}

/// What a cluster was created with, as far as recreating it needs. The node container keeps
/// its CPUs and memory but not the rest: its image reference loses the tag (it reads
/// `kindest/node@sha256:<digest>`), and nothing records a CNI manifest. From container 1.7 the
/// clusters service stores the CNI and Kubernetes version, which win over what Orchard
/// remembers. The workers are the ones the cluster has now, grouped by size, else the stored
/// count, else what Orchard remembers.
struct ClusterRecreateSettings: Equatable, Identifiable {
    enum NodeImage: Equatable {
        /// The plugin's own default, so no `--node-image` is needed.
        case pluginDefault
        /// A reference `k8s create` accepts, tag included.
        case reference(String)
        /// Only the untagged reference the node carries, which 1.5.0 refuses: the user has to
        /// say which version it was.
        case untagged(String)
    }

    let name: String
    /// The control plane's CPUs and memory, read off its node. Nil for a cluster with no node
    /// left to read them from, which then gets container's defaults.
    let cpus: Int?
    let memoryGiB: Int?
    let nodeImage: NodeImage
    let cni: ClusterCNI
    /// One group per worker size. On 1.7 a group read off live workers carries their size;
    /// below 1.7 there is one unsized group, as every worker matches the control plane.
    let workerGroups: [ClusterWorkerGroup]
    /// Whether the nodes use the Mac's image store (`--shared-image-store`, container 1.7).
    var sharedImageStore: Bool = false

    var id: String { name }
    var workers: Int { workerGroups.reduce(0) { $0 + $1.count } }
}

/// Owns Kubernetes-cluster lifecycle, driven through the `container cluster` CLI plugin,
/// since the plugin has no XPC API. Cluster *state* is not owned here: clusters are derived
/// from the container list (the nodes are ordinary containers with plugin labels), so
/// views group `ContainerListService.containers` via `K8sCluster.group`.
@MainActor
final class ClusterService: ObservableObject {
    @Published var pluginAvailability: K8sPluginAvailability = .unknown
    /// True while a create is in flight. Creates are slow (node image pull + kubeadm
    /// bootstrap), so this drives a persistent spinner rather than a sheet-local one.
    @Published var isCreating = false
    /// Running clusters created with no CNI whose nodes aren't all Ready yet: waiting for the
    /// user to install one. Kept up to date by `refreshCNIReadiness(of:)`.
    @Published var awaitingCNI: Set<String> = []
    /// Cluster names with a delete currently in flight.
    @Published var busyClusters: Set<String> = []
    /// True while a load-image is in flight.
    @Published var isLoadingImage = false
    /// The installed plugin's default node image, from its `create --help`. Nil
    /// until probed, or when the help could not be read (e.g. the system is stopped).
    @Published var pluginDefaultNodeImage: String?
    /// Recent `kindest/node` versions for the Create Cluster sheet. Empty until fetched, and
    /// left empty offline: the sheet then offers the plugin default and a custom image only.
    @Published var nodeImageOptions: [K8sNodeImageOption] = []
    /// The node picked under its cluster in the Clusters list, whose container the detail then
    /// shows; nil shows the cluster itself. Kept here rather than as another layout binding,
    /// like `ComposeService.selectedProject`.
    @Published var selectedNode: String?
    /// Clusters whose nodes the Clusters list shows under them. Kept beside `selectedNode`, so a
    /// tab switch can't hide a selected node in a collapsed cluster. Collapsed by default.
    @Published var expandedClusters: Set<String> = []
    /// What the clusters service stored for each cluster, by name, from `cluster ls --format
    /// json` (container 1.7). Empty below 1.7, while the system is stopped, and after a failed
    /// or unreadable list, so the Clusters tab then works from the container list as before.
    @Published var storedConfigurations: [String: StoredClusterConfiguration] = [:]
    /// True when `storedConfigurations` is the result of a successful `cluster ls`. Until then
    /// a cluster without a record can't be told apart from one made before 1.7.
    @Published private(set) var storedConfigurationsLoaded = false
    /// Bumped by each load and reset, so an older `cluster ls` that finishes last can't
    /// overwrite a newer result: one started before a delete would bring the cluster back.
    private var storedConfigurationGeneration: UInt64 = 0
    /// The clusters the node containers made up at the last successful load, so
    /// `containersChanged` only reloads when a cluster comes or goes.
    private var storedConfigurationClusterNames: Set<String>?
    /// The clusters a `containersChanged` load is running for, so repeated changes to the
    /// same clusters don't start another.
    private var storedConfigurationPendingNames: Set<String>?

    /// Overridable for tests, which must not reach Docker Hub.
    var fetchNodeImageTags: @Sendable () async throws -> [K8sNodeImageCatalog.HubTag] = {
        try await K8sNodeImageCatalog.fetchTags()
    }

    private let runner: CommandRunner
    private let settings: SettingsStore
    private let alertCenter: AlertCenter
    private let defaults: UserDefaults
    /// Clusters created with no CNI whose nodes have all been Ready, so they aren't checked
    /// again. In memory only: after a relaunch each is checked once more and lands back here.
    private var cniReadyClusters: Set<String> = []
    /// Bumped per name on each create and delete, so a readiness check that was in flight
    /// across a recreate can't apply the old cluster's result to the new one.
    private var cniGenerations: [String: Int] = [:]
    /// Views showing clusters, between `beginCNIChecks` and `endCNIChecks`.
    private var cniCheckConsumers = 0
    private var cniCheckTask: Task<Void, Never>?

    /// Refresh the container list after a lifecycle change. Set by the owner.
    var reloadContainers: () async -> Void = {}
    /// The ids of the containers that exist now. A cluster's name is its control-plane
    /// container's id, so a create under a taken name is one the CLI will refuse. Set by the owner.
    var existingContainerIDs: @MainActor () -> Set<String> = { [] }
    /// The clusters there are now, for the CNI readiness check. Set by the owner.
    var currentClusters: @MainActor () -> [K8sCluster] = { [] }
    /// The installed container version, which decides the plugin's command. Set by the owner.
    var containerVersion: @MainActor () -> String? = { nil }

    init(runner: CommandRunner, settings: SettingsStore, alertCenter: AlertCenter, defaults: UserDefaults = .standard) {
        self.runner = runner
        self.settings = settings
        self.alertCenter = alertCenter
        self.defaults = defaults
    }

    // MARK: - Remembered create options

    /// The node image, CNI manifest and worker count each cluster was created with through
    /// Orchard, keyed by cluster name. The image and CNI don't survive on the node container in
    /// a usable form, and the worker count is lost with any worker that failed to come up.
    private static let createOptionsKey = "clusterCreateOptions"

    private struct RememberedOptions: Codable {
        let nodeImage: String?
        /// A CNI manifest's path; nil for kindnet or no CNI.
        let cni: String?
        /// Nil in options saved before workers existed.
        let workers: Int?
        /// The worker groups with their sizes (container 1.7). Nil in options saved before
        /// worker sizing existed, which then read as one unsized group of `workers`.
        let workerGroups: [ClusterWorkerGroup]?
        /// True for a cluster created with no CNI. Separate from `cni` so it can never be taken
        /// for a path, and nil in options saved before it existed.
        let noCNI: Bool?
        /// Whether the cluster was created with `--shared-image-store`. Nil in options saved
        /// before it existed.
        let sharedImageStore: Bool?

        init(nodeImage: String?, cni: ClusterCNI, workerGroups: [ClusterWorkerGroup], sharedImageStore: Bool) {
            self.nodeImage = nodeImage
            self.workers = workerGroups.reduce(0) { $0 + $1.count }
            self.workerGroups = workerGroups.isEmpty ? nil : workerGroups
            self.sharedImageStore = sharedImageStore
            switch cni {
            case .kindnet:
                self.cni = nil
                self.noCNI = nil
            case .manifest(let path):
                self.cni = path
                self.noCNI = nil
            case .userInstalled:
                self.cni = nil
                self.noCNI = true
            }
        }

        var clusterCNI: ClusterCNI {
            if noCNI == true { return .userInstalled }
            return cni.map { .manifest($0) } ?? .kindnet
        }

        var rememberedWorkerGroups: [ClusterWorkerGroup] {
            if let workerGroups { return workerGroups }
            guard let workers, workers > 0 else { return [] }
            return [ClusterWorkerGroup(count: workers)]
        }
    }

    private func rememberedOptions(for name: String) -> RememberedOptions? {
        guard let data = defaults.data(forKey: Self.createOptionsKey),
              let all = try? JSONDecoder().decode([String: RememberedOptions].self, from: data)
        else { return nil }
        return all[name]
    }

    private func setRememberedOptions(_ options: RememberedOptions?, for name: String) {
        var all = (defaults.data(forKey: Self.createOptionsKey))
            .flatMap { try? JSONDecoder().decode([String: RememberedOptions].self, from: $0) } ?? [:]
        all[name] = options
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.createOptionsKey)
        }
    }

    /// `recreateSettings(for:)` once the plugin default and version list are loaded, which
    /// the digest matching needs. Loads them only if the sheet has not already.
    func prepareRecreate(_ cluster: K8sCluster) async -> ClusterRecreateSettings {
        if pluginDefaultNodeImage == nil || nodeImageOptions.isEmpty {
            await loadNodeImageOptions()
        }
        return recreateSettings(for: cluster)
    }

    /// How to recreate `cluster` as it was. Resources come from the control-plane node. The
    /// Kubernetes version comes from the clusters service's stored configuration (1.7) when
    /// there is one. Otherwise the image comes from what Orchard remembers, else from the
    /// node's digest: matching the plugin default or a listed version recovers the tag, and
    /// anything else is `untagged`.
    func recreateSettings(for cluster: K8sCluster) -> ClusterRecreateSettings {
        let node = cluster.controlPlane?.container ?? cluster.nodes.first?.container
        let resources = node?.configuration.resources
        let stored = cluster.stored
        // A remembered entry under a name the clusters service stored differently is from an
        // older cluster of that name, deleted and made again outside Orchard.
        let remembered = rememberedOptions(for: cluster.name).flatMap { options -> RememberedOptions? in
            guard let stored else { return options }
            if let image = options.nodeImage, K8sNodeImageCatalog.tag(of: image) != stored.kubernetesVersion { return nil }
            return options.clusterCNI == stored.clusterCNI ? options : nil
        }
        let cpus = resources?.cpus
        let memoryGiB = resources.map { max(1, $0.memoryInBytes / 1_073_741_824) }

        let nodeImage: ClusterRecreateSettings.NodeImage
        if let stored {
            nodeImage = storedNodeImage(version: stored.kubernetesVersion, remembered: remembered?.nodeImage, node: node)
        } else if let remembered {
            nodeImage = remembered.nodeImage.map { .reference($0) } ?? .pluginDefault
        } else if let image = node?.configuration.image {
            let digest = image.descriptor.digest
            if let pluginDefault = pluginDefaultNodeImage, pluginDefault.hasSuffix("@\(digest)") {
                nodeImage = .pluginDefault
            } else if let option = nodeImageOptions.first(where: { $0.reference.hasSuffix("@\(digest)") }) {
                nodeImage = .reference(option.reference)
            } else if K8sNodeImageCatalog.tag(of: image.reference) != nil {
                nodeImage = .reference(image.reference)
            } else {
                nodeImage = .untagged(image.reference)
            }
        } else {
            nodeImage = .pluginDefault
        }

        let sharedImageStore: Bool
        if !cluster.nodes.isEmpty {
            sharedImageStore = cluster.usesSharedImageStore
        } else {
            sharedImageStore = stored?.sharedImageStore ?? remembered?.sharedImageStore ?? false
        }

        return ClusterRecreateSettings(
            name: cluster.name, cpus: cpus, memoryGiB: memoryGiB,
            nodeImage: nodeImage, cni: stored?.clusterCNI ?? remembered?.clusterCNI ?? .kindnet,
            workerGroups: recreateWorkerGroups(cluster: cluster, remembered: remembered?.rememberedWorkerGroups ?? []),
            // Likewise the node's mount wins, and the stored or remembered choice covers a
            // cluster with no node left to read it from.
            sharedImageStore: sharedImageStore)
    }

    /// The workers to recreate. The live workers win: unlike the image they can be read off
    /// the cluster, and a remembered count is stale after a delete and create outside Orchard.
    /// On 1.7 they carry their sizes, one group per size. When the stored record (1.7) has more
    /// workers than are left, the missing ones are added back rather than lost: sized as
    /// remembered when the remembered groups add up to the stored count, else like the workers
    /// left when they are all one size, else as an unsized group, which gets container's
    /// defaults. A cluster with no stored record and no workers
    /// left falls back to what Orchard remembers. Below 1.7 there are no sizes to keep.
    private func recreateWorkerGroups(cluster: K8sCluster, remembered: [ClusterWorkerGroup]) -> [ClusterWorkerGroup] {
        let live = ClusterWorkerGroup.groups(of: cluster.workers)
        let liveCount = cluster.workers.count
        let rememberedCount = remembered.reduce(0) { $0 + $1.count }
        let groups: [ClusterWorkerGroup]
        if let stored = cluster.stored, stored.workerCount > liveCount {
            let missing = stored.workerCount - liveCount
            // Remembered was checked against the record in `recreateSettings`, so when it adds
            // up to the stored count it describes the whole cluster as it was made.
            if rememberedCount == stored.workerCount {
                groups = remembered
            } else if live.count == 1, var only = live.first {
                // Workers left all one size, as one `--workers` group makes them: the missing
                // ones were most likely that size too, and the sheet keeps one editable group.
                only.count += missing
                groups = [only]
            } else {
                groups = live + [ClusterWorkerGroup(count: missing)]
            }
        } else if liveCount > 0 {
            groups = live
        } else if cluster.stored != nil {
            groups = []
        } else {
            groups = remembered
        }
        guard supportsWorkerSizing else {
            let total = groups.reduce(0) { $0 + $1.count }
            return total > 0 ? [ClusterWorkerGroup(count: total)] : []
        }
        return groups
    }

    /// The node image for a cluster whose stored configuration names its Kubernetes version:
    /// the remembered image if it carries that version, the plugin default or a listed
    /// version with it, else the node's own repository (or kindest/node) at that tag.
    private func storedNodeImage(version: String, remembered: String?, node: Container?) -> ClusterRecreateSettings.NodeImage {
        if let remembered, K8sNodeImageCatalog.tag(of: remembered) == version {
            return .reference(remembered)
        }
        if let pluginDefault = pluginDefaultNodeImage, K8sNodeImageCatalog.tag(of: pluginDefault) == version {
            return .pluginDefault
        }
        if let option = nodeImageOptions.first(where: { $0.version == version }) {
            return .reference(option.reference)
        }
        let repository = node.map { K8sNodeImageCatalog.repository(of: $0.configuration.image.reference) } ?? "docker.io/kindest/node"
        return .reference("\(repository):\(version)")
    }

    /// Container 1.6.0 added worker nodes (`k8s create --workers`, `k8s load-image --node`).
    /// Orchard still runs against 1.5.x, which refuses both flags, so the controls are gated on
    /// the installed version. Nil (the system is stopped) or an unparseable version is false.
    nonisolated static func supportsWorkerNodes(containerVersion: String?) -> Bool {
        isContainerVersion(containerVersion, atLeast: [1, 6])
    }

    /// Container 1.6.0 added `k8s create --cni NONE` (apple/container#2277); 1.5.x would take
    /// `NONE` for a manifest path and fail. Gated like `supportsWorkerNodes`.
    nonisolated static func supportsNoCNI(containerVersion: String?) -> Bool {
        isContainerVersion(containerVersion, atLeast: [1, 6])
    }

    /// Container 1.7 replaced `cluster load-image` with `cluster create --shared-image-store`
    /// (apple/container#2437), which lets the nodes pull from the Mac's own image store. Load
    /// Image is offered below 1.7 only, and the create option from 1.7.
    nonisolated static func supportsSharedImageStore(containerVersion: String?) -> Bool {
        isContainerVersion(containerVersion, atLeast: [1, 7])
    }

    var supportsSharedImageStore: Bool { Self.supportsSharedImageStore(containerVersion: containerVersion()) }

    /// Container 1.7 sizes worker groups apart from the control plane
    /// (`--workers count=<n>,cpus=<n>,memory=<size>`, apple/container#2448). Before, every
    /// worker matched the control plane and `--workers` took a plain count only.
    nonisolated static func supportsWorkerSizing(containerVersion: String?) -> Bool {
        isContainerVersion(containerVersion, atLeast: [1, 7])
    }

    var supportsWorkerSizing: Bool { Self.supportsWorkerSizing(containerVersion: containerVersion()) }

    /// Container 1.7's clusters service stores each cluster's configuration, which
    /// `cluster ls --format json` returns (apple/container#2451). Gated with worker sizing.
    nonisolated static func supportsStoredClusterConfiguration(containerVersion: String?) -> Bool {
        isContainerVersion(containerVersion, atLeast: [1, 7])
    }

    /// The `--workers` arguments for `groups`. From 1.7 each group is its own `--workers`, a
    /// plain count when it has no size. Below 1.7 the sizes are dropped and the total goes as
    /// one plain count, the only form those versions accept. Empty groups are left out, and
    /// no workers at all sends no flag.
    nonisolated static func workerArguments(_ groups: [ClusterWorkerGroup], containerVersion: String?) -> [String] {
        let groups = groups.filter { $0.count > 0 }
        guard !groups.isEmpty else { return [] }
        guard supportsWorkerSizing(containerVersion: containerVersion) else {
            return ["--workers", String(groups.reduce(0) { $0 + $1.count })]
        }
        return groups.flatMap { ["--workers", $0.argument] }
    }

    /// Why Load Image is gone on 1.7, wherever it would have been.
    nonisolated static let loadImageRemovedHelp = "Apple container 1.7 removed Load Image. A cluster created with Use local images pulls from this Mac's images instead."

    /// The plugin's subcommand: container 1.6.1 renamed `k8s` to `cluster` (apple/container#2427).
    /// Nil (the system is stopped) or an unparseable version is `k8s`, like the other gates.
    nonisolated static func pluginCommand(containerVersion: String?) -> String {
        isContainerVersion(containerVersion, atLeast: [1, 6, 1]) ? K8sCluster.pluginName : K8sCluster.legacyPluginName
    }

    /// The plugin's own default cluster name, which moved with the rename: `cluster-dev`, `k8s-dev` before.
    nonisolated static func defaultClusterName(containerVersion: String?) -> String {
        "\(pluginCommand(containerVersion: containerVersion))-dev"
    }

    /// The plugin's subcommand on this install. Every CLI call starts with it.
    var pluginCommand: String { Self.pluginCommand(containerVersion: containerVersion()) }

    /// A cluster made by the `k8s` plugin on an install that now runs `cluster`. The CLI only
    /// sees `cluster`-labelled nodes, so its delete, load-image and write-config can't find it:
    /// Orchard deletes its nodes directly, and Recreate brings it back under the new label.
    nonisolated static func isStranded(_ cluster: K8sCluster, containerVersion: String?) -> Bool {
        cluster.isLegacy && pluginCommand(containerVersion: containerVersion) == K8sCluster.pluginName
    }

    /// A cluster with nodes but no stored configuration on 1.7 or later, once `cluster ls` has
    /// been read: made before 1.7, so `cluster ls` doesn't list it (apple/container#2451). Its
    /// delete and write-config still work. Never true before a successful load, or after a
    /// failed one, when a missing record says nothing.
    nonisolated static func isUnlisted(_ cluster: K8sCluster, containerVersion: String?, storedConfigurationsLoaded: Bool) -> Bool {
        storedConfigurationsLoaded && supportsStoredClusterConfiguration(containerVersion: containerVersion)
            && cluster.stored == nil && !cluster.nodes.isEmpty
    }

    /// "Kubernetes v1.35.5 · 3 nodes", or "Kubernetes cluster · 3 nodes" when the version isn't known.
    nonisolated static func subtitle(for cluster: K8sCluster) -> String {
        let nodes = cluster.nodes.count == 1 ? "1 node" : "\(cluster.nodes.count) nodes"
        guard let version = cluster.stored?.kubernetesVersion else { return "Kubernetes cluster · \(nodes)" }
        return "Kubernetes \(version) · \(nodes)"
    }

    func isStranded(_ cluster: K8sCluster) -> Bool {
        Self.isStranded(cluster, containerVersion: containerVersion())
    }

    /// Why a stranded cluster's image and kubeconfig actions are off, wherever they are.
    nonisolated static let strandedHelp = "Made by an older Apple container, whose cluster plugin can't see it. Recreate it to use this."

    /// Apple container's guide to using your own CNI, linked wherever Orchard offers one.
    nonisolated static let cniDocsURL = URL(string: "https://github.com/apple/container/blob/main/docs/kubernetes.md#custom-cni")!

    /// The kubeconfig file `container cluster write-config` writes to by default.
    nonisolated static var kubeconfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kube/config").path
    }

    /// Shell command for a terminal pre-configured for a cluster: select the cluster's
    /// kubectl context (write-config names it after the control-plane container), then
    /// hand over to an interactive shell.
    nonisolated static func kubectlTerminalCommand(cluster: String) -> String {
        // && so a failed context switch (e.g. kubeconfig not written yet) surfaces
        // instead of silently leaving the shell on the previously active cluster.
        "kubectl config use-context \(SystemCommandRunner.shellQuote(cluster)) && exec ${SHELL:-/bin/zsh}"
    }

    /// Probe whether the cluster plugin is installed by running its `list`.
    /// Cheap enough to re-run whenever the Clusters tab appears; only a positive
    /// "plugin not found" marks it missing, so a stopped system stays `.unknown`.
    func probePluginAvailability() async {
        let command = pluginCommand
        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: [command, "list"])
            if !result.failed {
                pluginAvailability = .available
                await loadStoredConfigurations()
                return
            }
            // 1.4.1 said "Plugin 'container-k8s' not found."; 1.5.0 says "unknown command 'k8s'",
            // and 1.6.1 the same for `cluster`.
            // Both come from the same branch, after the plugin loader exists, so neither is
            // the stopped-system case ("Plugins are unavailable").
            let stderr = (result.stderr ?? "").lowercased()
            if (stderr.contains("plugin") && stderr.contains("not found"))
                || stderr.contains("unknown command '\(command)'") {
                pluginAvailability = .missingPlugin
            } else {
                pluginAvailability = .unknown
            }
        } catch {
            pluginAvailability = .unknown
            Log.containers.error("Cluster plugin probe could not run: \(error.localizedDescription)")
        }
    }

    // MARK: - Stored configurations (1.7)

    /// The clusters `containers` make up, with what the clusters service stored for each.
    /// Every view listing clusters goes through this rather than `K8sCluster.group` alone.
    func clusters(from containers: [Container]) -> [K8sCluster] {
        K8sCluster.group(containers: containers, stored: storedConfigurations)
    }

    /// Load `storedConfigurations` from `cluster ls --format json`. Below 1.7 it is emptied
    /// without running anything. A failed run or unparseable output (the system stopped, say)
    /// is logged and empties it too, so nothing stale is shown: no record is shown as a
    /// cluster with no nodes, and none is called unlisted. Only the newest load is applied.
    /// `clusterNames` is what the node containers made up when it was asked for, recorded on
    /// success for `containersChanged`.
    func loadStoredConfigurations(clusterNames: Set<String>? = nil) async {
        storedConfigurationGeneration &+= 1
        let generation = storedConfigurationGeneration
        guard Self.supportsStoredClusterConfiguration(containerVersion: containerVersion()) else {
            resetStoredConfigurations()
            return
        }
        var loaded: [StoredClusterConfiguration]?
        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: [pluginCommand, "list", "--format", "json"])
            if result.failed {
                Log.containers.error("cluster list failed (\(result.exitCode)): \(result.stderr ?? "")")
            } else {
                loaded = StoredClusterConfiguration.parseList(json: result.stdout ?? "")
                if loaded == nil { Log.containers.error("cluster list output could not be parsed") }
            }
        } catch {
            Log.containers.error("cluster list could not run: \(error.localizedDescription)")
        }
        guard generation == storedConfigurationGeneration else { return }
        guard let loaded else {
            resetStoredConfigurations()
            return
        }
        storedConfigurations = Dictionary(loaded.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        storedConfigurationsLoaded = true
        storedConfigurationClusterNames = clusterNames
    }

    /// Forget every stored configuration and stop any load in flight from applying. On a
    /// system stop, since a stopped cluster's nodes leave the container list and its record
    /// would otherwise read as a cluster whose nodes are gone.
    func resetStoredConfigurations() {
        storedConfigurationGeneration &+= 1
        storedConfigurations = [:]
        storedConfigurationsLoaded = false
        storedConfigurationClusterNames = nil
        storedConfigurationPendingNames = nil
    }

    /// Reload `storedConfigurations` when the clusters the node containers make up have
    /// changed since the last successful load, so a cluster made or deleted with the CLI picks
    /// up its stored configuration without waiting for the Clusters tab. A failed load is
    /// tried again on the next change. Called on each container list change.
    func containersChanged(_ containers: [Container]) {
        let names = Set(containers.compactMap(K8sCluster.clusterName(for:)))
        if storedConfigurationsLoaded && names == storedConfigurationClusterNames { return }
        guard names != storedConfigurationPendingNames else { return }
        storedConfigurationPendingNames = names
        Task {
            await loadStoredConfigurations(clusterNames: names)
            if storedConfigurationPendingNames == names { storedConfigurationPendingNames = nil }
        }
    }

    /// Fill `pluginDefaultNodeImage` and `nodeImageOptions` for the Create Cluster sheet. A
    /// failure of either leaves what is already there, so a flaky network costs the version
    /// list and nothing else.
    func loadNodeImageOptions() async {
        if let help = try? await runner.run(
            program: settings.safeContainerBinaryPath(),
            arguments: [pluginCommand, "create", "--help"]),
           !help.failed {
            let text = [help.stdout, help.stderr].compactMap { $0 }.joined(separator: "\n")
            pluginDefaultNodeImage = K8sNodeImageCatalog.parsePluginDefault(helpText: text)
        }
        do {
            nodeImageOptions = K8sNodeImageCatalog.options(from: try await fetchNodeImageTags())
        } catch {
            Log.containers.error("kindest/node tag fetch failed: \(error.localizedDescription)")
        }
    }

    /// Create and start a cluster (`container cluster create`). Slow: pulls the kindest/node
    /// image on first use and bootstraps kubeadm. Returns true on success.
    ///
    /// A `.manifest` CNI is a host path applied instead of the default kindnet (1.5.0). Nothing
    /// checks that it suits the cluster; a bad one fails late, at the apply step. With
    /// `.userInstalled` (1.6.0) the CLI installs no CNI and returns without waiting for the
    /// nodes, which stay NotReady until the user applies one: see `awaitingCNI`.
    ///
    /// `workerGroups` adds worker nodes (1.6.0): see `workerArguments`. No workers leaves the
    /// flag out, the CLI's own default, so a 1.5.x install never sees it. On 1.7 a sized group
    /// sizes its workers apart from the control plane, which `cpus` and `memory` then size.
    ///
    /// `sharedImageStore` lets the nodes pull from the Mac's image store (1.7). It is only ever
    /// passed on 1.7 or later, whatever the caller asks for.
    @discardableResult
    func create(
        name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI = .kindnet,
        workerGroups: [ClusterWorkerGroup] = [], sharedImageStore: Bool = false
    ) async -> Bool {
        // A taken name fails in the CLI, and must not first overwrite what the existing
        // cluster was created with: its Recreate would then rebuild it from the wrong choices.
        // The list is refreshed first, since a container made outside Orchard since the last
        // poll would otherwise be missed. A failed refresh leaves the cached list to check.
        await reloadContainers()
        return await performCreate(
            name: name, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cni, workerGroups: workerGroups,
            sharedImageStore: sharedImageStore, rememberOptions: !existingContainerIDs().contains(name))
    }

    /// `create` with one unsized group of `workers`.
    @discardableResult
    func create(
        name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI = .kindnet, workers: Int,
        sharedImageStore: Bool = false
    ) async -> Bool {
        await create(
            name: name, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cni,
            workerGroups: workers > 0 ? [ClusterWorkerGroup(count: workers)] : [], sharedImageStore: sharedImageStore)
    }

    /// `create`, with the options' save decided by the caller. Recreate always saves: its
    /// delete has succeeded, though the container list may not have caught up yet.
    private func performCreate(
        name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI, workerGroups: [ClusterWorkerGroup],
        sharedImageStore: Bool, rememberOptions: Bool
    ) async -> Bool {
        let sharedImageStore = sharedImageStore && supportsSharedImageStore
        let workerGroups = workerGroups.filter { $0.count > 0 }
        var arguments = [pluginCommand, "create", "--name", name]
        if let cpus { arguments += ["--cpus", String(cpus)] }
        if let memory, !memory.isEmpty { arguments += ["--memory", memory] }
        if let nodeImage, !nodeImage.isEmpty { arguments += ["--node-image", nodeImage] }
        switch cni {
        case .kindnet: break
        case .manifest(let path): if !path.isEmpty { arguments += ["--cni", path] }
        case .userInstalled: arguments += ["--cni", "NONE"]
        }
        arguments += Self.workerArguments(workerGroups, containerVersion: containerVersion())
        if sharedImageStore { arguments.append("--shared-image-store") }

        isCreating = true
        defer { isCreating = false }
        // Remembered before the run, so a create that fails partway can still be recreated
        // with the same choices. Cleared again on delete.
        if rememberOptions {
            setRememberedOptions(
                RememberedOptions(nodeImage: nodeImage?.isEmpty == false ? nodeImage : nil,
                                  cni: cni, workerGroups: workerGroups, sharedImageStore: sharedImageStore),
                for: name)
        }
        // A recreate starts the wait again; anything else under this name has stopped waiting.
        cniGenerations[name, default: 0] += 1
        cniReadyClusters.remove(name)
        awaitingCNI.remove(name)
        let created = await runClusterCommand(arguments, failureVerb: "create cluster") { result in
            // Node prep aborts with the output of the step *before* the one that failed, so
            // the raw stderr would tell the user a sysctl they cannot act on. Everything the
            // plugin prints, progress and error alike, goes to stderr; stdout is checked too
            // so a change upstream does not silently drop the match.
            let output = [result.stderr, result.stdout].compactMap { $0 }.joined(separator: "\n")
            guard Self.outputIndicatesNodePrepFailure(output) else { return nil }
            return .k8sNodePrepFailed(cluster: name)
        }
        // The CLI returned before the nodes were Ready, since that needs a CNI, so the wait is
        // certain without checking. A create under a taken name failed above and never gets here.
        if created && cni == .userInstalled {
            awaitingCNI.insert(name)
        }
        // A create that failed partway may still have stored its configuration.
        await loadStoredConfigurations()
        return created
    }

    /// True when a `container cluster create` failure is the node-preparation abort. Node prep is
    /// one `set -e` script, so an abort reports the accumulated output of the steps that
    /// already succeeded (`net.ipv4.ip_forward = 1`, a sysctl that worked) rather than the
    /// command that failed. Matched on the one phrase the CLI does report accurately.
    ///
    /// Until 1.5.0 the usual cause was a pre-1.3.0 guest kernel without nftables, which the
    /// hard-coded `iptables-nft` calls needed (apple/container#2120). Node prep now uses the
    /// node image's own iptables backend, so that kernel works and nothing here blames it.
    nonisolated static func outputIndicatesNodePrepFailure(_ output: String) -> Bool {
        output.lowercased().contains("node prep failed")
    }

    // No start: container 1.5.0 removed `container k8s start`, so a stopped cluster can only
    // be deleted and created again (apple/container#2290).

    func delete(name: String) async {
        busyClusters.insert(name)
        defer { busyClusters.remove(name) }
        if await runClusterCommand(await deleteArguments(name), failureVerb: "delete cluster") {
            setRememberedOptions(nil, for: name)
            cniGenerations[name, default: 0] += 1
            awaitingCNI.remove(name)
            cniReadyClusters.remove(name)
        }
        await loadStoredConfigurations()
    }

    /// Delete the cluster and create it again under the same name: the only way back for a
    /// stopped cluster since `k8s start` went (apple/container#2290). One action, so nobody
    /// has to delete first and then retype what they created. Stops if the delete fails,
    /// which leaves the cluster as it was.
    @discardableResult
    func recreate(
        name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI,
        workerGroups: [ClusterWorkerGroup] = [], sharedImageStore: Bool = false
    ) async -> Bool {
        busyClusters.insert(name)
        defer { busyClusters.remove(name) }
        let deleted = await runClusterCommand(
            await deleteArguments(name), failureVerb: "delete cluster", reloadOnSuccess: false)
        guard deleted else { return false }
        return await performCreate(
            name: name, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cni, workerGroups: workerGroups,
            sharedImageStore: sharedImageStore, rememberOptions: true)
    }

    /// `recreate` with one unsized group of `workers`.
    @discardableResult
    func recreate(
        name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI, workers: Int,
        sharedImageStore: Bool = false
    ) async -> Bool {
        await recreate(
            name: name, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cni,
            workerGroups: workers > 0 ? [ClusterWorkerGroup(count: workers)] : [], sharedImageStore: sharedImageStore)
    }

    /// The plugin's delete, or for a stranded cluster a forced delete of each node container,
    /// since the plugin's delete can't see them. The list is refreshed first, as for `create`:
    /// a cached one missing the cluster would pick the plugin's delete, which refuses it.
    private func deleteArguments(_ name: String) async -> [String] {
        await reloadContainers()
        if let cluster = currentClusters().first(where: { $0.name == name }), isStranded(cluster) {
            return ["delete", "--force"] + cluster.nodes.map(\.id)
        }
        return [pluginCommand, "delete", "--name", name]
    }

    // MARK: - Waiting for a CNI

    /// How often `awaitingCNI` is refreshed while a view showing clusters is on screen.
    private static let cniCheckInterval: Duration = .seconds(10)

    /// Call when a view showing clusters appears: the list or a cluster's detail, either of
    /// which can be on screen without the other. Checks run every `cniCheckInterval` until the
    /// last such view calls `endCNIChecks`, as `StatsService.beginSampling` counts its views.
    func beginCNIChecks() {
        cniCheckConsumers += 1
        guard cniCheckTask == nil else { return }
        cniCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshCNIReadiness(of: self.currentClusters())
                try? await Task.sleep(for: Self.cniCheckInterval)
            }
        }
    }

    func endCNIChecks() {
        cniCheckConsumers = max(0, cniCheckConsumers - 1)
        guard cniCheckConsumers == 0 else { return }
        cniCheckTask?.cancel()
        cniCheckTask = nil
    }

    /// Check the clusters created with no CNI that aren't known to be Ready yet, and update
    /// `awaitingCNI`. Only running clusters Orchard remembers creating with no CNI are checked,
    /// so the rest cost nothing. Once a cluster's nodes are all Ready it isn't checked again.
    func refreshCNIReadiness(of clusters: [K8sCluster]) async {
        for cluster in clusters {
            guard rememberedOptions(for: cluster.name)?.clusterCNI == .userInstalled,
                  !cniReadyClusters.contains(cluster.name)
            else {
                awaitingCNI.remove(cluster.name)
                continue
            }
            // A stopped cluster shows as stopped, and its Recreate starts the wait again.
            guard cluster.isRunning, let controlPlane = cluster.controlPlane else {
                awaitingCNI.remove(cluster.name)
                continue
            }
            let generation = cniGenerations[cluster.name]
            let ready = await nodesReady(controlPlane: controlPlane.id, expectedNodes: cluster.nodes.count)
            // Deleted or created again while the check ran: the result is the old cluster's.
            guard cniGenerations[cluster.name] == generation else { continue }
            if ready == true {
                cniReadyClusters.insert(cluster.name)
                awaitingCNI.remove(cluster.name)
            } else {
                // A failed check (API server still starting, say) keeps the wait: no CNI has
                // been seen working, and the next check will tell.
                awaitingCNI.insert(cluster.name)
            }
        }
        // Clusters gone from the list stop waiting.
        awaitingCNI.formIntersection(clusters.map(\.name))
    }

    /// Whether the cluster's nodes are all Ready, asked of the API server from inside the
    /// control-plane node, whose kindest/node image carries kubectl and the admin kubeconfig.
    /// That needs neither kubectl on the Mac nor a written kubeconfig. Nil when it can't tell.
    /// The request timeout keeps an API server that accepts but never answers from stalling
    /// the checks: the runner itself waits as long as the process runs.
    private func nodesReady(controlPlane: String, expectedNodes: Int) async -> Bool? {
        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["exec", controlPlane,
                            "kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf",
                            "--request-timeout", "5s", "get", "nodes", "-o", "json"])
            guard !result.failed, let stdout = result.stdout else { return nil }
            return Self.allNodesReady(kubectlNodesJSON: stdout, expectedNodes: expectedNodes)
        } catch {
            Log.containers.error("CNI readiness check for \(controlPlane) could not run: \(error.localizedDescription)")
            return nil
        }
    }

    private struct KubectlNodeList: Decodable {
        struct Node: Decodable {
            struct Status: Decodable {
                struct Condition: Decodable {
                    let type: String
                    let status: String
                }
                let conditions: [Condition]?
            }
            let status: Status?
        }
        let items: [Node]
    }

    /// Parse `kubectl get nodes -o json`: true when at least `expectedNodes` nodes are listed
    /// and every one has a `Ready` condition of `True`. A worker that hasn't registered yet
    /// would otherwise let a cluster count as Ready early. Nil when the output isn't a node list.
    nonisolated static func allNodesReady(kubectlNodesJSON: String, expectedNodes: Int) -> Bool? {
        guard let list = try? JSONDecoder().decode(KubectlNodeList.self, from: Data(kubectlNodesJSON.utf8)) else {
            return nil
        }
        guard list.items.count >= max(expectedNodes, 1) else { return false }
        return list.items.allSatisfy { node in
            node.status?.conditions?.contains { $0.type == "Ready" && $0.status == "True" } == true
        }
    }

    /// Load a local image into the cluster's containerd (`container cluster load-image`),
    /// so cluster workloads can use images built or pulled in Orchard. Empty `nodes` loads it
    /// into every node; otherwise only into those named, one `--node` each (1.6.0).
    ///
    /// Refused from container 1.7, which removed the subcommand: the views don't offer it there,
    /// and this keeps any other path from running a command that can only fail.
    @discardableResult
    func loadImage(cluster: String, reference: String, nodes: [String] = []) async -> Bool {
        guard !supportsSharedImageStore else {
            alertCenter.error(Self.loadImageRemovedHelp)
            return false
        }
        isLoadingImage = true
        defer { isLoadingImage = false }
        return await runClusterCommand(
            [pluginCommand, "load-image", "--name", cluster] + nodes.flatMap { ["--node", $0] } + [reference],
            failureVerb: "load image", reloadOnSuccess: false)
    }

    /// Write/merge the cluster's context into the kubeconfig (`container cluster write-config`).
    @discardableResult
    func writeConfig(cluster: String) async -> Bool {
        await runClusterCommand(
            [pluginCommand, "write-config", "--name", cluster],
            failureVerb: "write kubeconfig", reloadOnSuccess: false)
    }

    /// `classifyFailure` gets first refusal on a non-zero exit: returning an `OrchardError`
    /// replaces the generic `.cliFailed` dump, which is how a known upstream failure mode gets
    /// copy a user can act on. Returning nil falls back to the raw CLI text.
    @discardableResult
    private func runClusterCommand(
        _ arguments: [String],
        failureVerb: String,
        reloadOnSuccess: Bool = true,
        classifyFailure: ((ProcessResult) -> OrchardError?)? = nil
    ) async -> Bool {
        alertCenter.dismiss()
        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: arguments)
            if result.failed {
                alertCenter.error(classifyFailure?(result) ?? .cliFailed(
                    command: arguments.prefix(2).joined(separator: " "),
                    exitCode: result.exitCode,
                    stderr: result.stderr))
                return false
            }
            if reloadOnSuccess { await reloadContainers() }
            return true
        } catch {
            alertCenter.error("Failed to \(failureVerb): \(error.localizedDescription)")
            Log.containers.error("Error running \(arguments.joined(separator: " ")): \(error.localizedDescription)")
            return false
        }
    }
}
