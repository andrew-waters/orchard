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

    #expect(settings == ClusterRecreateSettings(name: "k8s-dev", cpus: 2, memoryGiB: 2, nodeImage: .pluginDefault, cni: nil))
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
        nodeImage: "docker.io/kindest/node:v1.34.11@sha256:zz", cni: "/Users/me/cilium.yaml")

    let settings = service.clusterService.recreateSettings(for: try stoppedCluster(digest: "sha256:zz"))

    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.34.11@sha256:zz"))
    #expect(settings.cni == "/Users/me/cilium.yaml")
}

@MainActor
@Test("Recreate settings: deleting a cluster forgets what it was created with")
func deleteForgetsRememberedOptions() async throws {
    let service = makeService()
    await service.clusterService.create(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: "/Users/me/cilium.yaml")
    await service.clusterService.delete(name: "k8s-dev")

    #expect(service.clusterService.recreateSettings(for: try stoppedCluster()).cni == nil)
}

@MainActor
@Test("Recreate: deletes, then creates with the same settings, as one action")
func recreateDeletesThenCreates() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    let ok = await service.clusterService.recreate(
        name: "k8s-dev", cpus: 2, memory: "2GB", nodeImage: nil, cni: nil)

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

    let ok = await service.clusterService.recreate(name: "k8s-dev", cpus: nil, memory: nil, nodeImage: nil, cni: nil)

    #expect(!ok)
    #expect(!runner.calls.contains { $0.starts(with: ["k8s", "create"]) })
}
