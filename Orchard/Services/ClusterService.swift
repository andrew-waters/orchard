import Foundation

// MARK: - Cluster model

/// A node container in a local Kubernetes cluster, as created by the `container k8s`
/// plugin. Wraps the container snapshot with the cluster it belongs to.
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

/// A local Kubernetes cluster: the k8s-plugin-owned node containers grouped by cluster.
/// The cluster's name is its control-plane container's id; workers are named
/// `<cluster>-worker-N`. Grouping mirrors `K8sHelper.buildK8sRows` in apple/container.
struct K8sCluster: Identifiable, Equatable {
    static let pluginName = "k8s"
    static let controlPlaneRole = "control-plane"
    /// The most workers `container k8s create --workers` accepts (1.6.0).
    static let maxWorkers = 1024

    let name: String
    let nodes: [K8sClusterNode]

    var id: String { name }
    var controlPlane: K8sClusterNode? { nodes.first(where: { $0.isControlPlane }) }
    var workers: [K8sClusterNode] { nodes.filter { !$0.isControlPlane } }
    /// A cluster is running when its control plane is; workers can lag behind.
    var isRunning: Bool { controlPlane?.isRunning ?? false }
    var status: String { controlPlane?.container.status ?? nodes.first?.container.status ?? "unknown" }

    /// The cluster a k8s node container belongs to: a control plane names its own
    /// cluster; a worker derives it from `<cluster>-worker-N`, falling back to the id.
    /// Nil for containers the k8s plugin doesn't own.
    static func clusterName(for container: Container) -> String? {
        guard container.owningPlugin == pluginName else { return nil }
        let id = container.configuration.id
        if container.pluginRoles.contains(controlPlaneRole) { return id }
        let derived = id.components(separatedBy: "-worker-").dropLast().joined(separator: "-worker-")
        return derived.isEmpty ? id : derived
    }

    /// Group the k8s plugin's node containers into clusters. Pure so it can be unit
    /// tested; containers not owned by the k8s plugin are ignored.
    static func group(containers: [Container]) -> [K8sCluster] {
        let nodes = containers.filter { $0.owningPlugin == pluginName }
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

/// Whether the `container k8s` plugin is usable on this install.
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
}

/// What a cluster was created with, as far as recreating it needs. The node container keeps
/// its CPUs and memory but not the rest: its image reference loses the tag (it reads
/// `kindest/node@sha256:<digest>`), and nothing records a CNI manifest. The worker count is
/// the workers the cluster has now, else what Orchard remembers.
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
    let cpus: Int
    let memoryGiB: Int
    let nodeImage: NodeImage
    let cni: ClusterCNI
    let workers: Int

    var id: String { name }
}

/// Owns Kubernetes-cluster lifecycle, driven through the `container k8s` CLI plugin —
/// the plugin has no XPC API. Cluster *state* is not owned here: clusters are derived
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
    /// The installed plugin's default node image, from `container k8s create --help`. Nil
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
        /// True for a cluster created with no CNI. Separate from `cni` so it can never be taken
        /// for a path, and nil in options saved before it existed.
        let noCNI: Bool?

        init(nodeImage: String?, cni: ClusterCNI, workers: Int) {
            self.nodeImage = nodeImage
            self.workers = workers
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
    /// image comes from what Orchard remembers, else from the node's digest: matching the
    /// plugin default or a listed version recovers the tag, and anything else is `untagged`.
    func recreateSettings(for cluster: K8sCluster) -> ClusterRecreateSettings {
        let node = cluster.controlPlane?.container ?? cluster.nodes.first?.container
        let resources = node?.configuration.resources
        let remembered = rememberedOptions(for: cluster.name)
        let cpus = resources?.cpus ?? 2
        let memoryGiB = max(1, (resources?.memoryInBytes ?? 4 * 1_073_741_824) / 1_073_741_824)

        let nodeImage: ClusterRecreateSettings.NodeImage
        if let remembered {
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

        return ClusterRecreateSettings(
            name: cluster.name, cpus: cpus, memoryGiB: memoryGiB,
            nodeImage: nodeImage, cni: remembered?.clusterCNI ?? .kindnet,
            // The live count wins: unlike the image and CNI it can be read off the cluster, and a
            // remembered one is stale after a delete and create outside Orchard. Remembered only
            // covers a cluster left with no workers.
            workers: cluster.workers.isEmpty ? (remembered?.workers ?? 0) : cluster.workers.count)
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

    private nonisolated static func isContainerVersion(_ version: String?, atLeast minimum: [Int]) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, !parts.contains(nil) else { return false }
        let numbers = parts.compactMap { $0 }
        return !numbers.lexicographicallyPrecedes(minimum)
    }

    /// Apple container's guide to using your own CNI, linked wherever Orchard offers one.
    nonisolated static let cniDocsURL = URL(string: "https://github.com/apple/container/blob/main/docs/kubernetes.md#custom-cni")!

    /// The kubeconfig file `container k8s write-config` writes to by default.
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

    /// Probe whether the k8s plugin is installed by running `container k8s list`.
    /// Cheap enough to re-run whenever the Clusters tab appears; only a positive
    /// "plugin not found" marks it missing, so a stopped system stays `.unknown`.
    func probePluginAvailability() async {
        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["k8s", "list"])
            if !result.failed {
                pluginAvailability = .available
                return
            }
            // 1.4.1 said "Plugin 'container-k8s' not found."; 1.5.0 says "unknown command 'k8s'".
            // Both come from the same branch, after the plugin loader exists, so neither is
            // the stopped-system case ("Plugins are unavailable").
            let stderr = (result.stderr ?? "").lowercased()
            if (stderr.contains("plugin") && stderr.contains("not found"))
                || stderr.contains("unknown command '\(K8sCluster.pluginName)'") {
                pluginAvailability = .missingPlugin
            } else {
                pluginAvailability = .unknown
            }
        } catch {
            pluginAvailability = .unknown
            Log.containers.error("k8s plugin probe could not run: \(error.localizedDescription)")
        }
    }

    /// Fill `pluginDefaultNodeImage` and `nodeImageOptions` for the Create Cluster sheet. A
    /// failure of either leaves what is already there, so a flaky network costs the version
    /// list and nothing else.
    func loadNodeImageOptions() async {
        if let help = try? await runner.run(
            program: settings.safeContainerBinaryPath(),
            arguments: ["k8s", "create", "--help"]),
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

    /// Create and start a cluster (`container k8s create`). Slow: pulls the kindest/node
    /// image on first use and bootstraps kubeadm. Returns true on success.
    ///
    /// A `.manifest` CNI is a host path applied instead of the default kindnet (1.5.0). Nothing
    /// checks that it suits the cluster; a bad one fails late, at the apply step. With
    /// `.userInstalled` (1.6.0) the CLI installs no CNI and returns without waiting for the
    /// nodes, which stay NotReady until the user applies one: see `awaitingCNI`.
    ///
    /// `workers` above 0 adds that many worker nodes (1.6.0). The flag is left out at 0, the
    /// CLI's own default, so a 1.5.x install never sees it.
    @discardableResult
    func create(name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI = .kindnet, workers: Int = 0) async -> Bool {
        // A taken name fails in the CLI, and must not first overwrite what the existing
        // cluster was created with: its Recreate would then rebuild it from the wrong choices.
        // The list is refreshed first, since a container made outside Orchard since the last
        // poll would otherwise be missed. A failed refresh leaves the cached list to check.
        await reloadContainers()
        return await performCreate(
            name: name, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cni, workers: workers,
            rememberOptions: !existingContainerIDs().contains(name))
    }

    /// `create`, with the options' save decided by the caller. Recreate always saves: its
    /// delete has succeeded, though the container list may not have caught up yet.
    private func performCreate(
        name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI, workers: Int,
        rememberOptions: Bool
    ) async -> Bool {
        var arguments = ["k8s", "create", "--name", name]
        if let cpus { arguments += ["--cpus", String(cpus)] }
        if let memory, !memory.isEmpty { arguments += ["--memory", memory] }
        if let nodeImage, !nodeImage.isEmpty { arguments += ["--node-image", nodeImage] }
        switch cni {
        case .kindnet: break
        case .manifest(let path): if !path.isEmpty { arguments += ["--cni", path] }
        case .userInstalled: arguments += ["--cni", "NONE"]
        }
        if workers > 0 { arguments += ["--workers", String(workers)] }

        isCreating = true
        defer { isCreating = false }
        // Remembered before the run, so a create that fails partway can still be recreated
        // with the same choices. Cleared again on delete.
        if rememberOptions {
            setRememberedOptions(
                RememberedOptions(nodeImage: nodeImage?.isEmpty == false ? nodeImage : nil,
                                  cni: cni, workers: workers),
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
        return created
    }

    /// True when a `container k8s create` failure is the node-preparation abort. Node prep is
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
        if await runClusterCommand(["k8s", "delete", "--name", name], failureVerb: "delete cluster") {
            setRememberedOptions(nil, for: name)
            cniGenerations[name, default: 0] += 1
            awaitingCNI.remove(name)
            cniReadyClusters.remove(name)
        }
    }

    /// Delete the cluster and create it again under the same name: the only way back for a
    /// stopped cluster since `k8s start` went (apple/container#2290). One action, so nobody
    /// has to delete first and then retype what they created. Stops if the delete fails,
    /// which leaves the cluster as it was.
    @discardableResult
    func recreate(name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: ClusterCNI, workers: Int = 0) async -> Bool {
        busyClusters.insert(name)
        defer { busyClusters.remove(name) }
        let deleted = await runClusterCommand(
            ["k8s", "delete", "--name", name], failureVerb: "delete cluster", reloadOnSuccess: false)
        guard deleted else { return false }
        return await performCreate(
            name: name, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cni, workers: workers,
            rememberOptions: true)
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

    /// Load a local image into the cluster's containerd (`container k8s load-image`),
    /// so cluster workloads can use images built or pulled in Orchard. Empty `nodes` loads it
    /// into every node; otherwise only into those named, one `--node` each (1.6.0).
    @discardableResult
    func loadImage(cluster: String, reference: String, nodes: [String] = []) async -> Bool {
        isLoadingImage = true
        defer { isLoadingImage = false }
        return await runClusterCommand(
            ["k8s", "load-image", "--name", cluster] + nodes.flatMap { ["--node", $0] } + [reference],
            failureVerb: "load image", reloadOnSuccess: false)
    }

    /// Write/merge the cluster's context into the kubeconfig (`container k8s write-config`).
    @discardableResult
    func writeConfig(cluster: String) async -> Bool {
        await runClusterCommand(
            ["k8s", "write-config", "--name", cluster],
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
