import Foundation

// MARK: - Cluster model

/// A node container in a local Kubernetes cluster, as created by the `container k8s`
/// plugin. Wraps the container snapshot with the cluster it belongs to.
struct K8sClusterNode: Identifiable, Equatable {
    let clusterName: String
    let container: Container

    var id: String { container.configuration.id }
    var role: String? { container.pluginRole }
    var isControlPlane: Bool { role == K8sCluster.controlPlaneRole }
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

    /// Group the k8s plugin's node containers into clusters. Pure so it can be unit
    /// tested; containers not owned by the k8s plugin are ignored.
    static func group(containers: [Container]) -> [K8sCluster] {
        let nodes = containers.filter { $0.owningPlugin == pluginName }
        var controlPlanes: [Container] = []
        var workers: [Container] = []
        for node in nodes {
            if node.pluginRole == controlPlaneRole {
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
            let clusterName = w.configuration.id
                .components(separatedBy: "-worker-").dropLast().joined(separator: "-worker-")
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
    /// Cluster names with a start/delete currently in flight.
    @Published var busyClusters: Set<String> = []
    /// True while a load-image is in flight.
    @Published var isLoadingImage = false

    private let runner: CommandRunner
    private let settings: SettingsStore
    private let alertCenter: AlertCenter

    /// Refresh the container list after a lifecycle change. Set by the owner.
    var reloadContainers: () async -> Void = {}

    init(runner: CommandRunner, settings: SettingsStore, alertCenter: AlertCenter) {
        self.runner = runner
        self.settings = settings
        self.alertCenter = alertCenter
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
        "kubectl config use-context \(SystemCommandRunner.shellQuote(cluster)) ; exec ${SHELL:-/bin/zsh}"
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
            let stderr = (result.stderr ?? "").lowercased()
            if stderr.contains("plugin"), stderr.contains("not found") {
                pluginAvailability = .missingPlugin
            } else {
                pluginAvailability = .unknown
            }
        } catch {
            pluginAvailability = .unknown
            Log.containers.error("k8s plugin probe could not run: \(error.localizedDescription)")
        }
    }

    /// Create and start a cluster (`container k8s create`). Slow: pulls the kindest/node
    /// image on first use and bootstraps kubeadm. Returns true on success.
    @discardableResult
    func create(name: String, cpus: Int?, memory: String?, nodeImage: String?) async -> Bool {
        var arguments = ["k8s", "create", "--name", name]
        if let cpus { arguments += ["--cpus", String(cpus)] }
        if let memory, !memory.isEmpty { arguments += ["--memory", memory] }
        if let nodeImage, !nodeImage.isEmpty { arguments += ["--node-image", nodeImage] }

        isCreating = true
        defer { isCreating = false }
        return await runClusterCommand(arguments, failureVerb: "create cluster")
    }

    func start(name: String) async {
        busyClusters.insert(name)
        defer { busyClusters.remove(name) }
        await runClusterCommand(["k8s", "start", "--name", name], failureVerb: "start cluster")
    }

    func delete(name: String) async {
        busyClusters.insert(name)
        defer { busyClusters.remove(name) }
        await runClusterCommand(["k8s", "delete", "--name", name], failureVerb: "delete cluster")
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

    @discardableResult
    private func runClusterCommand(_ arguments: [String], failureVerb: String, reloadOnSuccess: Bool = true) async -> Bool {
        alertCenter.dismiss()
        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: arguments)
            if result.failed {
                alertCenter.error(.cliFailed(
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
