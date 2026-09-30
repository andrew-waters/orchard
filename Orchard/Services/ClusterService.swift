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

/// What a cluster was created with, as far as recreating it needs. The node container keeps
/// its CPUs and memory but not the rest: its image reference loses the tag (it reads
/// `kindest/node@sha256:<digest>`), and nothing records a CNI manifest.
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
    let cni: String?

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

    /// Overridable for tests, which must not reach Docker Hub.
    var fetchNodeImageTags: @Sendable () async throws -> [K8sNodeImageCatalog.HubTag] = {
        try await K8sNodeImageCatalog.fetchTags()
    }

    private let runner: CommandRunner
    private let settings: SettingsStore
    private let alertCenter: AlertCenter
    private let defaults: UserDefaults

    /// Refresh the container list after a lifecycle change. Set by the owner.
    var reloadContainers: () async -> Void = {}

    init(runner: CommandRunner, settings: SettingsStore, alertCenter: AlertCenter, defaults: UserDefaults = .standard) {
        self.runner = runner
        self.settings = settings
        self.alertCenter = alertCenter
        self.defaults = defaults
    }

    // MARK: - Remembered create options

    /// The node image and CNI manifest each cluster was created with through Orchard, keyed
    /// by cluster name, since neither survives on the node container in a usable form.
    private static let createOptionsKey = "clusterCreateOptions"

    private struct RememberedOptions: Codable {
        let nodeImage: String?
        let cni: String?
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
            nodeImage: nodeImage, cni: remembered?.cni)
    }

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
    /// `cni` is a host path to a CNI manifest applied instead of the default kindnet (1.5.0).
    /// Nothing checks that it suits the cluster; a bad one fails late, at the apply step.
    @discardableResult
    func create(name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: String? = nil) async -> Bool {
        var arguments = ["k8s", "create", "--name", name]
        if let cpus { arguments += ["--cpus", String(cpus)] }
        if let memory, !memory.isEmpty { arguments += ["--memory", memory] }
        if let nodeImage, !nodeImage.isEmpty { arguments += ["--node-image", nodeImage] }
        if let cni, !cni.isEmpty { arguments += ["--cni", cni] }

        isCreating = true
        defer { isCreating = false }
        // Remembered before the run, so a create that fails partway can still be recreated
        // with the same choices. Cleared again on delete.
        setRememberedOptions(
            RememberedOptions(nodeImage: nodeImage?.isEmpty == false ? nodeImage : nil,
                              cni: cni?.isEmpty == false ? cni : nil),
            for: name)
        return await runClusterCommand(arguments, failureVerb: "create cluster") { result in
            // Node prep aborts with the output of the step *before* the one that failed, so
            // the raw stderr would tell the user a sysctl they cannot act on. Everything the
            // plugin prints, progress and error alike, goes to stderr; stdout is checked too
            // so a change upstream does not silently drop the match.
            let output = [result.stderr, result.stdout].compactMap { $0 }.joined(separator: "\n")
            guard Self.outputIndicatesNodePrepFailure(output) else { return nil }
            return .k8sNodePrepFailed(cluster: name)
        }
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
        }
    }

    /// Delete the cluster and create it again under the same name: the only way back for a
    /// stopped cluster since `k8s start` went (apple/container#2290). One action, so nobody
    /// has to delete first and then retype what they created. Stops if the delete fails,
    /// which leaves the cluster as it was.
    @discardableResult
    func recreate(name: String, cpus: Int?, memory: String?, nodeImage: String?, cni: String?) async -> Bool {
        busyClusters.insert(name)
        defer { busyClusters.remove(name) }
        let deleted = await runClusterCommand(
            ["k8s", "delete", "--name", name], failureVerb: "delete cluster", reloadOnSuccess: false)
        guard deleted else { return false }
        return await create(name: name, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cni)
    }

    /// Load a local image into the cluster's containerd (`container k8s load-image`),
    /// so cluster workloads can use images built or pulled in Orchard.
    @discardableResult
    func loadImage(cluster: String, reference: String) async -> Bool {
        isLoadingImage = true
        defer { isLoadingImage = false }
        return await runClusterCommand(
            ["k8s", "load-image", "--name", cluster, reference],
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
