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
    #expect(command.contains("kubectl config use-context 'k8s-dev'"))
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
}

@MainActor
@Test("Start, delete, load-image, and write-config drive the expected CLI subcommands")
func lifecycleCommands() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.clusterService.start(name: "k8s-dev")
    await service.clusterService.delete(name: "k8s-dev")
    _ = await service.clusterService.loadImage(cluster: "k8s-dev", reference: "demo-api:latest")
    _ = await service.clusterService.writeConfig(cluster: "k8s-dev")

    #expect(runner.calls.contains(["k8s", "start", "--name", "k8s-dev"]))
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
