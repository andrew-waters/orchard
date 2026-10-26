import Testing
import Foundation
@testable import Orchard

// MARK: - Fixtures

private func k8sNode(_ id: String, role: String? = nil, status: String = "running") throws -> Container {
    var labels = ["com.apple.container.plugin": "k8s"]
    if let role { labels["com.apple.container.resource.role"] = role }
    return try makeContainer(id: id, status: status, labels: labels)
}

// MARK: - Grouping (mirrors K8sHelper.buildK8sRows upstream)

@Test("Grouping: a control plane and its workers form one cluster, workers sorted")
func groupControlPlaneWithWorkers() throws {
    let containers = [
        try k8sNode("k8s-dev-worker-2"),
        try k8sNode("k8s-dev", role: "control-plane"),
        try k8sNode("k8s-dev-worker-1"),
        try makeContainer(id: "web", status: "running"),
    ]
    let clusters = K8sCluster.group(containers: containers)
    #expect(clusters.count == 1)
    #expect(clusters.first?.name == "k8s-dev")
    #expect(clusters.first?.nodes.map(\.id) == ["k8s-dev", "k8s-dev-worker-1", "k8s-dev-worker-2"])
    #expect(clusters.first?.controlPlane?.id == "k8s-dev")
    #expect(clusters.first?.workers.map(\.id) == ["k8s-dev-worker-1", "k8s-dev-worker-2"])
}

@Test("Grouping: a single node that is both control plane and worker is the cluster's control plane")
func groupSingleNodeCombinedRole() throws {
    // The default `container k8s create` cluster: one node labelled "control-plane,worker".
    // Matching the label against "control-plane" classified it as a worker, which left the
    // cluster with no control plane, so it read as stopped while running and offered Start.
    let clusters = K8sCluster.group(containers: [
        try k8sNode("k8s-dev", role: "control-plane,worker"),
    ])
    #expect(clusters.count == 1)
    #expect(clusters.first?.name == "k8s-dev")
    #expect(clusters.first?.controlPlane?.id == "k8s-dev")
    #expect(clusters.first?.workers.isEmpty == true)
    #expect(clusters.first?.isRunning == true)
}

@Test("Grouping: a combined-role control plane still claims its workers")
func groupCombinedRoleWithWorkers() throws {
    let clusters = K8sCluster.group(containers: [
        try k8sNode("k8s-dev-worker-1"),
        try k8sNode("k8s-dev", role: "control-plane,worker"),
    ])
    #expect(clusters.count == 1)
    #expect(clusters.first?.nodes.map(\.id) == ["k8s-dev", "k8s-dev-worker-1"])
    #expect(clusters.first?.controlPlane?.id == "k8s-dev")
    #expect(clusters.first?.workers.map(\.id) == ["k8s-dev-worker-1"])
}

@Test("clusterName(for:): a combined-role node names its own cluster")
func clusterNameForCombinedRole() throws {
    #expect(K8sCluster.clusterName(for: try k8sNode("k8s-dev", role: "control-plane,worker")) == "k8s-dev")
}

@Test("Grouping: multiple clusters sort by name and don't claim each other's workers")
func groupMultipleClusters() throws {
    let containers = [
        try k8sNode("staging", role: "control-plane"),
        try k8sNode("dev", role: "control-plane"),
        try k8sNode("staging-worker-1"),
        try k8sNode("dev-worker-1"),
    ]
    let clusters = K8sCluster.group(containers: containers)
    #expect(clusters.map(\.name) == ["dev", "staging"])
    #expect(clusters[0].nodes.map(\.id) == ["dev", "dev-worker-1"])
    #expect(clusters[1].nodes.map(\.id) == ["staging", "staging-worker-1"])
}

@Test("Grouping: workers without a control plane group under their derived cluster name")
func groupOrphanWorkers() throws {
    let containers = [
        try k8sNode("gone-worker-1"),
        try k8sNode("gone-worker-2"),
    ]
    let clusters = K8sCluster.group(containers: containers)
    #expect(clusters.count == 1)
    #expect(clusters.first?.name == "gone")
    #expect(clusters.first?.controlPlane == nil)
    #expect(clusters.first?.isRunning == false)   // no control plane → not running
}

@Test("Grouping: containers not owned by the k8s plugin are ignored")
func groupIgnoresNonPluginContainers() throws {
    let containers = [
        try makeContainer(id: "web", status: "running"),
        try makeContainer(id: "buildkit", status: "running",
                          labels: ["com.apple.container.resource.role": "builder"]),
    ]
    #expect(K8sCluster.group(containers: containers).isEmpty)
}

@Test("Cluster status follows the control plane")
func clusterStatusFollowsControlPlane() throws {
    let stopped = K8sCluster.group(containers: [
        try k8sNode("k8s-dev", role: "control-plane", status: "stopped"),
        try k8sNode("k8s-dev-worker-1", status: "running"),
    ])
    #expect(stopped.first?.isRunning == false)
    #expect(stopped.first?.status == "stopped")
}

// MARK: - kubectl helpers

@Test("kubectl terminal command selects the cluster context, quoted, then stays interactive")
func kubectlCommand() {
    let command = ClusterService.kubectlTerminalCommand(cluster: "k8s-dev")
    #expect(command.contains("kubectl config use-context 'k8s-dev' &&"))
    #expect(command.contains("exec ${SHELL"))
}

@Test("kubeconfig path is the CLI's default write target")
func kubeconfigPath() {
    #expect(ClusterService.kubeconfigPath.hasSuffix("/.kube/config"))
}

// MARK: - Plugin probe

@MainActor
@Test("Probe: exit 0 marks the plugin available")
func probeAvailable() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    await service.clusterService.probePluginAvailability()
    #expect(service.clusterService.pluginAvailability == .available)
    #expect(runner.calls.first == ["k8s", "list"])
}

@MainActor
@Test("Probe: the CLI's plugin-not-found error marks the plugin missing")
func probeMissingPlugin() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in
        ProcessResult(exitCode: 1, stdout: nil, stderr: "Error: Plugin 'container-k8s' not found.")
    }
    let service = makeService(runner: runner)
    await service.clusterService.probePluginAvailability()
    #expect(service.clusterService.pluginAvailability == .missingPlugin)
}

@MainActor
@Test("Probe: the 1.5.0 unknown-command error marks the plugin missing")
func probeMissingPluginUnknownCommand() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in
        // Verbatim shape of DefaultCommand's error in container 1.5.0.
        ProcessResult(exitCode: 1, stdout: nil, stderr: """
            Error: unknown command 'k8s'

            - If system services are not running, start them with: container system start

            If 'k8s' is a plugin, check that it exists under:
              - /Users/me/.local/libexec/container/plugins/k8s
              - /usr/local/libexec/container/plugins/k8s
            """)
    }
    let service = makeService(runner: runner)
    await service.clusterService.probePluginAvailability()
    #expect(service.clusterService.pluginAvailability == .missingPlugin)
}

@MainActor
@Test("Probe: the stopped-system error stays unknown, even though it names plugins")
func probeStoppedSystemStaysUnknown() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in
        ProcessResult(exitCode: 1, stdout: nil, stderr: """
            Error: Plugins are unavailable. Start the container system services and retry:

                container system start

            Check to see that the plugin exists under:
              - /usr/local/libexec/container/plugins/k8s
            """)
    }
    let service = makeService(runner: runner)
    await service.clusterService.probePluginAvailability()
    #expect(service.clusterService.pluginAvailability == .unknown)
}

@MainActor
@Test("Probe: other failures (e.g. system stopped) stay unknown, not missing")
func probeOtherFailureStaysUnknown() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in
        ProcessResult(exitCode: 1, stdout: nil, stderr: "XPC connection error")
    }
    let service = makeService(runner: runner)
    await service.clusterService.probePluginAvailability()
    #expect(service.clusterService.pluginAvailability == .unknown)
}

// MARK: - Lifecycle commands

@MainActor
@Test("Create: passes name and only the overridden options to the CLI")
func createPassesArguments() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    let okDefault = await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil)
    #expect(okDefault)
    #expect(runner.calls.first == ["k8s", "create", "--name", "k8s-dev"])

    let okCustom = await service.clusterService.create(name: "big", cpus: 8, memory: "8GB", nodeImage: "docker.io/kindest/node:v1.35.5")
    #expect(okCustom)
    #expect(runner.calls.last == ["k8s", "create", "--name", "big", "--cpus", "8", "--memory", "8GB", "--node-image", "docker.io/kindest/node:v1.35.5"])
}

@MainActor
@Test("Create: a CLI failure alerts and returns false")
func createFailureAlerts() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 1, stdout: nil, stderr: "boom") }
    let service = makeService(runner: runner)

    let ok = await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil)
    #expect(ok == false)
    #expect(service.alertCenter.current != nil)
    // An unclassified failure keeps the raw CLI text: the node-prep classifier must not
    // swallow everything that happens to fail.
    #expect(service.alertCenter.current?.message.contains("boom") == true)
}

/// Verbatim from `container k8s create` on 1.4.1, all of it on stderr. Only the "node prep
/// failed" phrase is accurate: the sysctl and the image tag are steps that succeeded.
private let nodePrepFailureStderr = """
    Preparing node: ["id": k8s-dev]
    [2/2] Running kubeadm init [7s]
    Error: node prep failed on k8s-dev: net.ipv4.ip_forward = 1
    registry.k8s.io/pause:3.10.1
    """

@MainActor
@Test("Create: a node-prep abort replaces the misleading output with its own message")
func createNodePrepFailureReplacesOutput() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 1, stdout: nil, stderr: nodePrepFailureStderr) }
    let service = makeService(runner: runner)

    let ok = await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil)
    #expect(ok == false)
    let message = service.alertCenter.current?.message ?? ""
    #expect(message.contains("k8s-dev"))
    // The line that sent people chasing a working sysctl never reaches them. Nor does a
    // kernel diagnosis: 1.5.0 node prep works on the pre-nftables kernel that used to fail.
    #expect(!message.contains("ip_forward"))
    #expect(!message.contains("nftables"))
}

@Test("Failure detection: the node-prep abort is recognised from the CLI's real output")
func detectsNodePrepFailure() {
    #expect(ClusterService.outputIndicatesNodePrepFailure(nodePrepFailureStderr))
}

@Test("Failure detection: unrelated failures are left to the generic CLI error")
func ignoresUnrelatedFailures() {
    for output in [
        "Error: failed to delete container (cause: \"notFound\")",
        "Error: HTTP request failed with response: 401 Unauthorized",
        "net.ipv4.ip_forward = 1",   // the misleading line alone is not the signature
        "",
    ] {
        #expect(!ClusterService.outputIndicatesNodePrepFailure(output))
    }
}

@MainActor
@Test("Delete, load-image, and write-config drive the expected CLI subcommands")
func lifecycleCommands() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.clusterService.delete(name: "k8s-dev")
    _ = await service.clusterService.loadImage(cluster: "k8s-dev", reference: "demo-api:latest")
    _ = await service.clusterService.writeConfig(cluster: "k8s-dev")

    #expect(runner.calls.contains(["k8s", "delete", "--name", "k8s-dev"]))
    #expect(runner.calls.contains(["k8s", "load-image", "--name", "k8s-dev", "demo-api:latest"]))
    #expect(runner.calls.contains(["k8s", "write-config", "--name", "k8s-dev"]))
}

@Test("Grouping: a k8s node without '-worker-' in its id falls back to the id as cluster name")
func groupOrphanWithoutWorkerSuffix() throws {
    let clusters = K8sCluster.group(containers: [try k8sNode("stray")])
    #expect(clusters.count == 1)
    #expect(clusters.first?.name == "stray")
    #expect(clusters.first?.nodes.map(\.id) == ["stray"])
}

@Test("clusterName(for:): control plane names itself, workers derive, others are nil")
func clusterNameForContainer() throws {
    #expect(K8sCluster.clusterName(for: try k8sNode("k8s-dev", role: "control-plane")) == "k8s-dev")
    #expect(K8sCluster.clusterName(for: try k8sNode("k8s-dev-worker-2")) == "k8s-dev")
    #expect(K8sCluster.clusterName(for: try k8sNode("stray")) == "stray")
    #expect(K8sCluster.clusterName(for: try makeContainer(id: "web", status: "running")) == nil)
}

// MARK: - Recreate

private let defaultNodeImage = "docker.io/kindest/node:v1.35.5@sha256:ce97"

/// A stopped single-node cluster as 1.5.0 leaves it: the image reference has lost its tag.
private func stoppedCluster(digest: String = "sha256:ce97") throws -> K8sCluster {
    let node = try makeContainer(
        id: "k8s-dev", status: "stopped",
        labels: ["com.apple.container.plugin": "k8s", "com.apple.container.resource.role": "control-plane,worker"],
        imageReference: "docker.io/kindest/node@\(digest)", imageDigest: digest,
        cpus: 2, memoryInBytes: 2 * 1_073_741_824)
    return try #require(K8sCluster.group(containers: [node]).first)
}

@MainActor
@Test("Recreate settings: resources come from the node, and the plugin default is matched by digest")
func recreateSettingsMatchPluginDefault() throws {
    let service = makeService()
    service.clusterService.pluginDefaultNodeImage = defaultNodeImage

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster())

    #expect(settings == ClusterRecreateSettings(name: "k8s-dev", cpus: 2, memoryGiB: 2, nodeImage: .pluginDefault, cni: .kindnet, workers: 0))
}

@MainActor
@Test("Recreate settings: a listed version is matched by digest, recovering its tag")
func recreateSettingsMatchListedVersion() throws {
    let service = makeService()
    service.clusterService.pluginDefaultNodeImage = defaultNodeImage
    service.clusterService.nodeImageOptions = [
        K8sNodeImageOption(version: "v1.37.0", reference: "docker.io/kindest/node:v1.37.0@sha256:a1"),
    ]

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster(digest: "sha256:a1"))

    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.37.0@sha256:a1"))
}

@MainActor
@Test("Recreate settings: an unknown digest is reported untagged, for the user to resolve")
func recreateSettingsUntagged() throws {
    let service = makeService()
    service.clusterService.pluginDefaultNodeImage = defaultNodeImage

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster(digest: "sha256:zz"))

    #expect(settings.nodeImage == .untagged("docker.io/kindest/node@sha256:zz"))
}

@MainActor
@Test("Recreate settings: what Orchard created the cluster with wins over digest matching")
func recreateSettingsPreferRemembered() async throws {
    let service = makeService()
    await service.clusterService.create(
        name: "k8s-dev", cpus: nil, memory: nil,
        nodeImage: "docker.io/kindest/node:v1.34.11@sha256:zz", cni: .manifest("/Users/me/cilium.yaml"))

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster(digest: "sha256:zz"))

    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.34.11@sha256:zz"))
    #expect(settings.cni == .manifest("/Users/me/cilium.yaml"))
}

@MainActor
@Test("Recreate settings: deleting a cluster forgets what it was created with")
func deleteForgetsRememberedOptions() async throws {
    let service = makeService()
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .manifest("/Users/me/cilium.yaml"))
    await service.clusterService.delete(name: "k8s-dev")

    #expect(service.clusterService.recreateSettings(for: try stoppedCluster()).cni == .kindnet)
}

@MainActor
@Test("Recreate: deletes, then creates with the same settings, as one action")
func recreateDeletesThenCreates() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    let ok = await service.clusterService.recreate(
        name: "k8s-dev", cpus: 2, memory: "2GB", nodeImage: nil, cni: .kindnet)

    #expect(ok)
    let calls = runner.calls
    let deleteAt = calls.firstIndex(of: ["k8s", "delete", "--name", "k8s-dev"])
    let createAt = calls.firstIndex(of: ["k8s", "create", "--name", "k8s-dev", "--cpus", "2", "--memory", "2GB"])
    #expect(deleteAt != nil && createAt != nil)
    #expect((deleteAt ?? .max) < (createAt ?? .min))
}

@MainActor
@Test("Recreate: a failed delete stops before creating anything")
func recreateStopsWhenDeleteFails() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, arguments in
        arguments.starts(with: ["k8s", "delete"])
            ? ProcessResult(exitCode: 1, stdout: nil, stderr: "Error: boom")
            : ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let service = makeService(runner: runner)

    let ok = await service.clusterService.recreate(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .kindnet)

    #expect(!ok)
    #expect(!runner.calls.contains { $0.starts(with: ["k8s", "create"]) })
}

@MainActor
@Test("Remembered options: a create under a taken name leaves the existing cluster's options alone")
func createUnderTakenNameKeepsRememberedOptions() async throws {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    await service.clusterService.create(
        name: "k8s-dev", cpus: nil, memory: nil,
        nodeImage: "docker.io/kindest/node:v1.37.0@sha256:a1", cni: .manifest("/Users/me/cilium.yaml"))
    // The node exists on the daemon but not yet in Orchard's cached list, as when it was made
    // since the last poll: create must refresh before it checks.
    backend.containers = [try stoppedCluster(digest: "sha256:a1").nodes[0].container]
    service.containerListService.containers = []

    // A second Create with the same name: the CLI refuses it, and it must not first
    // overwrite what the real k8s-dev was created with.
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .kindnet)

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster(digest: "sha256:a1"))
    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.37.0@sha256:a1"))
    #expect(settings.cni == .manifest("/Users/me/cilium.yaml"))
}

@MainActor
@Test("Remembered options: recreate records its new choices while the old node is still listed")
func recreateRecordsNewOptions() async throws {
    let service = makeService()
    // The list still shows the node: recreate doesn't reload between its delete and create.
    service.containerListService.containers = [try stoppedCluster().nodes[0].container]

    await service.clusterService.recreate(
        name: "k8s-dev", cpus: nil, memory: nil,
        nodeImage: "docker.io/kindest/node:v1.36.4@sha256:b4", cni: .manifest("/Users/me/calico.yaml"))

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster())
    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.36.4@sha256:b4"))
    #expect(settings.cni == .manifest("/Users/me/calico.yaml"))
}

// MARK: - Worker nodes (1.6.0)

@Test("Grouping: a 1.6.0 cluster with workers has a control-plane-only node and its workers")
func groupClusterWithWorkers() throws {
    // `k8s create --workers 2`: the control plane loses the worker role, the workers carry it alone.
    let clusters = K8sCluster.group(containers: [
        try k8sNode("k8s-dev-worker-1", role: "worker"),
        try k8sNode("k8s-dev", role: "control-plane"),
        try k8sNode("k8s-dev-worker-2", role: "worker"),
    ])
    #expect(clusters.count == 1)
    #expect(clusters.first?.controlPlane?.id == "k8s-dev")
    #expect(clusters.first?.workers.map(\.id) == ["k8s-dev-worker-1", "k8s-dev-worker-2"])
}

@Test("Worker nodes are offered from container 1.6.0, and not when the version is unknown")
func supportsWorkerNodesByVersion() {
    for version in ["1.6.0", "1.6.1", "1.10.0", "2.0", "2.0.0"] {
        #expect(ClusterService.supportsWorkerNodes(containerVersion: version), "\(version)")
    }
    for version in ["1.5.0", "1.5.10", "0.9.0", "1", "", "unknown", "1.6.0-beta"] {
        #expect(!ClusterService.supportsWorkerNodes(containerVersion: version), "\(version)")
    }
    #expect(!ClusterService.supportsWorkerNodes(containerVersion: nil))
}

@MainActor
@Test("Create: --workers is passed only when workers are asked for")
func createPassesWorkers() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, workers: 0)
    #expect(runner.calls.last == ["k8s", "create", "--name", "k8s-dev"])

    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, workers: 2)
    #expect(runner.calls.last == ["k8s", "create", "--name", "k8s-dev", "--workers", "2"])
}

@MainActor
@Test("Load image: one --node per chosen node, none for every node")
func loadImageTargetsNodes() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.clusterService.loadImage(cluster: "k8s-dev", reference: "demo-api:latest", nodes: [])
    #expect(runner.calls.last == ["k8s", "load-image", "--name", "k8s-dev", "demo-api:latest"])

    await service.clusterService.loadImage(
        cluster: "k8s-dev", reference: "demo-api:latest", nodes: ["k8s-dev-worker-1", "k8s-dev-worker-2"])
    #expect(runner.calls.last == [
        "k8s", "load-image", "--name", "k8s-dev",
        "--node", "k8s-dev-worker-1", "--node", "k8s-dev-worker-2", "demo-api:latest",
    ])
}

@MainActor
@Test("Recreate settings: the worker count is remembered, and recreate passes it on")
func recreateRemembersWorkers() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, workers: 3)

    // Only the control plane is listed, so the remembered count is all there is to go on.
    let settings = service.clusterService.recreateSettings(for: try stoppedCluster())
    #expect(settings.workers == 3)

    await service.clusterService.recreate(
        name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .kindnet, workers: settings.workers)
    #expect(runner.calls.last == ["k8s", "create", "--name", "k8s-dev", "--workers", "3"])
}

@MainActor
@Test("Recreate settings: with nothing remembered, the worker count is the workers the cluster has")
func recreateDerivesWorkers() throws {
    let service = makeService()
    let cluster = try #require(K8sCluster.group(containers: [
        try k8sNode("k8s-dev", role: "control-plane", status: "stopped"),
        try k8sNode("k8s-dev-worker-1", role: "worker", status: "stopped"),
        try k8sNode("k8s-dev-worker-2", role: "worker", status: "stopped"),
    ]).first)

    #expect(service.clusterService.recreateSettings(for: cluster).workers == 2)
}

@MainActor
@Test("Remembered options saved before workers existed still decode")
func rememberedOptionsWithoutWorkersDecode() throws {
    let defaults = ephemeralDefaults()
    defaults.set(Data(#"{"k8s-dev":{"cni":"/Users/me/cilium.yaml"}}"#.utf8), forKey: "clusterCreateOptions")
    let service = makeService(defaults: defaults)

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster())
    #expect(settings.cni == .manifest("/Users/me/cilium.yaml"))
    #expect(settings.workers == 0)
}

@MainActor
@Test("Recreate settings: the workers a cluster has beat a remembered count gone stale")
func recreatePrefersLiveWorkers() async throws {
    let service = makeService()
    // Created through Orchard with no workers, then deleted and created again with two from the CLI.
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, workers: 0)
    let cluster = try #require(K8sCluster.group(containers: [
        try k8sNode("k8s-dev", role: "control-plane", status: "stopped"),
        try k8sNode("k8s-dev-worker-1", role: "worker", status: "stopped"),
        try k8sNode("k8s-dev-worker-2", role: "worker", status: "stopped"),
    ]).first)

    #expect(service.clusterService.recreateSettings(for: cluster).workers == 2)
}

// MARK: - No CNI (1.6.0)

private func kubectlNodes(_ ready: [Bool]) -> String {
    let items = ready.enumerated().map { index, isReady in
        #"{"metadata":{"name":"node-\#(index)"},"status":{"conditions":[{"type":"MemoryPressure","status":"False"},{"type":"Ready","status":"\#(isReady ? "True" : "False")"}]}}"#
    }
    return #"{"apiVersion":"v1","kind":"List","items":[\#(items.joined(separator: ","))]}"#
}

private func runningCluster() throws -> K8sCluster {
    try #require(K8sCluster.group(containers: [
        try k8sNode("k8s-dev", role: "control-plane"),
        try k8sNode("k8s-dev-worker-1", role: "worker"),
    ]).first)
}

@Test("No CNI is offered from container 1.6.0, and not when the version is unknown")
func supportsNoCNIByVersion() {
    #expect(ClusterService.supportsNoCNI(containerVersion: "1.6.0"))
    #expect(ClusterService.supportsNoCNI(containerVersion: "2.0"))
    #expect(!ClusterService.supportsNoCNI(containerVersion: "1.5.10"))
    #expect(!ClusterService.supportsNoCNI(containerVersion: nil))
}

@MainActor
@Test("Create: no CNI passes --cni NONE, and the cluster waits for one straight away")
func createWithNoCNI() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .userInstalled)
    #expect(runner.calls.last == ["k8s", "create", "--name", "k8s-dev", "--cni", "NONE"])
    #expect(service.clusterService.awaitingCNI == ["k8s-dev"])
}

@MainActor
@Test("Create: a failed create with no CNI doesn't wait for one")
func failedCreateWithNoCNIDoesNotWait() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 1, stdout: nil, stderr: "boom") }
    let service = makeService(runner: runner)

    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .userInstalled)
    #expect(service.clusterService.awaitingCNI.isEmpty)
}

@MainActor
@Test("Recreate settings: no CNI is remembered apart from a manifest path, and recreate passes it on")
func recreateRemembersNoCNI() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .userInstalled)

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster())
    #expect(settings.cni == .userInstalled)

    await service.clusterService.recreate(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: settings.cni)
    #expect(runner.calls.last == ["k8s", "create", "--name", "k8s-dev", "--cni", "NONE"])
}

@Test("Node readiness: every node Ready, some NotReady, too few nodes, and output that isn't a node list")
func parsesNodeReadiness() {
    #expect(ClusterService.allNodesReady(kubectlNodesJSON: kubectlNodes([true, true]), expectedNodes: 2) == true)
    #expect(ClusterService.allNodesReady(kubectlNodesJSON: kubectlNodes([true, false]), expectedNodes: 2) == false)
    // A worker that hasn't registered yet: the one node listed is Ready, but the cluster isn't.
    #expect(ClusterService.allNodesReady(kubectlNodesJSON: kubectlNodes([true]), expectedNodes: 2) == false)
    #expect(ClusterService.allNodesReady(kubectlNodesJSON: kubectlNodes([]), expectedNodes: 0) == false)
    #expect(ClusterService.allNodesReady(kubectlNodesJSON: #"{"items":[{"status":{}}]}"#, expectedNodes: 1) == false)
    #expect(ClusterService.allNodesReady(kubectlNodesJSON: "The connection to the server was refused", expectedNodes: 1) == nil)
}

@MainActor
@Test("CNI readiness: checked inside the control plane until the nodes are Ready, then no more")
func cniReadinessClearsAndStops() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .userInstalled)
    let cluster = try runningCluster()

    runner.defaultResult = ProcessResult(exitCode: 0, stdout: kubectlNodes([false, false]), stderr: nil)
    await service.clusterService.refreshCNIReadiness(of: [cluster])
    #expect(runner.calls.last == [
        "exec", "k8s-dev", "kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf",
        "--request-timeout", "5s", "get", "nodes", "-o", "json",
    ])
    #expect(service.clusterService.awaitingCNI == ["k8s-dev"])

    // A failed check keeps the wait.
    runner.defaultResult = ProcessResult(exitCode: 1, stdout: nil, stderr: "connection refused")
    await service.clusterService.refreshCNIReadiness(of: [cluster])
    #expect(service.clusterService.awaitingCNI == ["k8s-dev"])

    runner.defaultResult = ProcessResult(exitCode: 0, stdout: kubectlNodes([true, true]), stderr: nil)
    await service.clusterService.refreshCNIReadiness(of: [cluster])
    #expect(service.clusterService.awaitingCNI.isEmpty)

    let callsAfterReady = runner.calls.count
    await service.clusterService.refreshCNIReadiness(of: [cluster])
    #expect(runner.calls.count == callsAfterReady)
    #expect(service.clusterService.awaitingCNI.isEmpty)
}

@MainActor
@Test("CNI readiness: clusters created with kindnet or a manifest, or not through Orchard, are never checked")
func cniReadinessSkipsOtherClusters() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    await service.clusterService.create(
        name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .manifest("/Users/me/cilium.yaml"))
    let callsAfterCreate = runner.calls.count

    let other = try #require(K8sCluster.group(containers: [try k8sNode("other", role: "control-plane")]).first)
    await service.clusterService.refreshCNIReadiness(of: [try runningCluster(), other])
    #expect(runner.calls.count == callsAfterCreate)
    #expect(service.clusterService.awaitingCNI.isEmpty)
}

@MainActor
@Test("CNI readiness: a stopped cluster isn't checked and doesn't read as waiting")
func cniReadinessSkipsStoppedClusters() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .userInstalled)
    let callsAfterCreate = runner.calls.count

    await service.clusterService.refreshCNIReadiness(of: [try stoppedCluster()])
    #expect(runner.calls.count == callsAfterCreate)
    #expect(service.clusterService.awaitingCNI.isEmpty)
}

@MainActor
@Test("CNI readiness: a check in flight across a recreate doesn't apply the old cluster's result")
func cniReadinessIgnoresResultFromBeforeRecreate() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .userInstalled)
    let cluster = try runningCluster()

    // The old cluster answers Ready, but only after it has been recreated with no CNI.
    let clusterService = service.clusterService
    runner.runHandler = { _, arguments in
        if arguments.first == "exec" {
            await clusterService.recreate(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .userInstalled)
            return ProcessResult(exitCode: 0, stdout: kubectlNodes([true, true]), stderr: nil)
        }
        return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    await service.clusterService.refreshCNIReadiness(of: [cluster])
    #expect(service.clusterService.awaitingCNI == ["k8s-dev"])

    // And the new cluster is still checked rather than taken as Ready.
    runner.runHandler = nil
    runner.defaultResult = ProcessResult(exitCode: 0, stdout: kubectlNodes([false, false]), stderr: nil)
    let callsBefore = runner.calls.count
    await service.clusterService.refreshCNIReadiness(of: [cluster])
    #expect(runner.calls.count == callsBefore + 1)
    #expect(service.clusterService.awaitingCNI == ["k8s-dev"])
}

// MARK: - The cluster rename (1.6.1)

private func clusterNode(_ id: String, role: String? = nil, status: String = "running") throws -> Container {
    var labels = ["com.apple.container.plugin": "cluster"]
    if let role { labels["com.apple.container.resource.role"] = role }
    return try makeContainer(id: id, status: status, labels: labels)
}

@Test("Plugin command: cluster from container 1.6.1, k8s before or when the version is unknown")
func pluginCommandByVersion() {
    #expect(ClusterService.pluginCommand(containerVersion: "1.6.1") == "cluster")
    #expect(ClusterService.pluginCommand(containerVersion: "1.7") == "cluster")
    #expect(ClusterService.pluginCommand(containerVersion: "1.6.0") == "k8s")
    #expect(ClusterService.pluginCommand(containerVersion: "1.6") == "k8s")
    #expect(ClusterService.pluginCommand(containerVersion: nil) == "k8s")
    #expect(ClusterService.defaultClusterName(containerVersion: "1.6.1") == "cluster-dev")
    #expect(ClusterService.defaultClusterName(containerVersion: "1.6.0") == "k8s-dev")
}

@MainActor
@Test("On 1.6.1 every plugin command is `cluster`")
func commandsOnRenamedPlugin() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.6.1"

    await service.clusterService.probePluginAvailability()
    await service.clusterService.create(name: "cluster-dev", cpus: nil, memory: nil, nodeImage: nil)
    _ = await service.clusterService.loadImage(cluster: "cluster-dev", reference: "demo-api:latest")
    _ = await service.clusterService.writeConfig(cluster: "cluster-dev")
    await service.clusterService.delete(name: "cluster-dev")

    #expect(service.clusterService.pluginAvailability == .available)
    #expect(runner.calls.contains(["cluster", "list"]))
    #expect(runner.calls.contains(["cluster", "create", "--name", "cluster-dev"]))
    #expect(runner.calls.contains(["cluster", "load-image", "--name", "cluster-dev", "demo-api:latest"]))
    #expect(runner.calls.contains(["cluster", "write-config", "--name", "cluster-dev"]))
    #expect(runner.calls.contains(["cluster", "delete", "--name", "cluster-dev"]))
    #expect(!runner.calls.contains { $0.first == "k8s" })
}

@MainActor
@Test("Probe: on 1.6.1 an unknown `cluster` command marks the plugin missing")
func probeMissingRenamedPlugin() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in
        ProcessResult(exitCode: 1, stdout: nil, stderr: "Error: unknown command 'cluster'")
    }
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.6.1"
    await service.clusterService.probePluginAvailability()
    #expect(service.clusterService.pluginAvailability == .missingPlugin)
}

@Test("Grouping: nodes labelled `cluster` group like `k8s` ones, and both labels can coexist")
func groupRenamedAndLegacyLabels() throws {
    let containers = [
        try clusterNode("cluster-dev", role: "control-plane"),
        try clusterNode("cluster-dev-worker-1", role: "worker"),
        try k8sNode("k8s-dev", role: "control-plane,worker"),
        try makeContainer(id: "web", status: "running"),
    ]
    let clusters = K8sCluster.group(containers: containers)
    #expect(clusters.map(\.name) == ["cluster-dev", "k8s-dev"])
    #expect(clusters.first?.nodes.map(\.id) == ["cluster-dev", "cluster-dev-worker-1"])
    #expect(clusters.map(\.isLegacy) == [false, true])
    #expect(try clusterNode("cluster-dev").isK8sNode)
    #expect(K8sCluster.clusterName(for: try clusterNode("cluster-dev-worker-1")) == "cluster-dev")
}

@Test("Stranded: only a k8s-labelled cluster on an install that runs `cluster`")
func strandedByVersion() throws {
    let legacy = try #require(K8sCluster.group(containers: [try k8sNode("k8s-dev", role: "control-plane")]).first)
    let renamed = try #require(K8sCluster.group(containers: [try clusterNode("cluster-dev", role: "control-plane")]).first)
    #expect(ClusterService.isStranded(legacy, containerVersion: "1.6.1"))
    #expect(!ClusterService.isStranded(legacy, containerVersion: "1.6.0"))
    #expect(!ClusterService.isStranded(legacy, containerVersion: nil))
    #expect(!ClusterService.isStranded(renamed, containerVersion: "1.6.1"))
}

@MainActor
@Test("Stranded: delete and recreate remove the nodes directly, and recreate creates under `cluster`")
func strandedDeleteAndRecreate() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.6.1"
    let legacy = try runningCluster()
    service.clusterService.currentClusters = { [legacy] }

    await service.clusterService.delete(name: "k8s-dev")
    #expect(runner.calls.last == ["delete", "--force", "k8s-dev", "k8s-dev-worker-1"])

    let ok = await service.clusterService.recreate(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: .kindnet, workers: 1)
    #expect(ok)
    let calls = runner.calls
    let deleteAt = calls.lastIndex(of: ["delete", "--force", "k8s-dev", "k8s-dev-worker-1"])
    let createAt = calls.firstIndex(of: ["cluster", "create", "--name", "k8s-dev", "--workers", "1"])
    #expect(deleteAt != nil && createAt != nil)
    #expect((deleteAt ?? .max) < (createAt ?? .min))
}

@MainActor
@Test("On 1.6.0 a k8s cluster is deleted through the plugin, as before")
func legacyDeleteOnOldInstall() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.6.0"
    let legacy = try runningCluster()
    service.clusterService.currentClusters = { [legacy] }

    await service.clusterService.delete(name: "k8s-dev")
    #expect(runner.calls.last == ["k8s", "delete", "--name", "k8s-dev"])
}
