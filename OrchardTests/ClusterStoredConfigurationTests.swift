import Testing
import Foundation
@testable import Orchard

// Container 1.7.1: worker groups sized apart from the control plane (apple/container#2448), and
// the clusters service's stored configuration from `cluster ls --format json` (apple/container#2451).

// MARK: - Fixtures

private func node(
    _ id: String, role: String, status: String = "stopped", cpus: Int = 2, memoryGiB: Int = 2,
    imageReference: String = "docker.io/kindest/node@sha256:zz", digest: String = "sha256:zz"
) throws -> Container {
    try makeContainer(
        id: id, status: status,
        labels: ["com.apple.container.plugin": "cluster", "com.apple.container.resource.role": role],
        imageReference: imageReference, imageDigest: digest,
        cpus: cpus, memoryInBytes: memoryGiB * 1_073_741_824)
}

/// `container cluster ls --format json` on 1.7.1, trimmed to two clusters: one with kindnet and
/// two workers, one with no CNI on a single node.
private let clusterListJSON = """
[{"configuration":{"cni":null,"creationDate":"2026-11-09T10:15:30Z","fqdn":null,"kubernetesVersion":"v1.35.5","labels":{},\
"name":"dev","nodes":[{"kind":"linux","name":"dev","roles":["control-plane"]},{"kind":"linux","name":"dev-worker-1","roles":["worker"]},\
{"kind":"linux","name":"dev-worker-2","roles":["worker"]}],"remove":false,"sharedImageStore":true},"id":"dev",\
"status":{"state":"running","nodes":[]}},\
{"configuration":{"cni":"NONE","creationDate":"2026-11-08T08:00:00Z","kubernetesVersion":"v1.34.11",\
"name":"bare","nodes":[{"name":"bare","roles":["control-plane","worker"]}]},"id":"bare","status":{}}]
"""

private func stored(_ json: String = clusterListJSON) throws -> [String: StoredClusterConfiguration] {
    let parsed = try #require(StoredClusterConfiguration.parseList(json: json))
    return Dictionary(uniqueKeysWithValues: parsed.map { ($0.name, $0) })
}

// MARK: - Worker arguments

@Test("Worker arguments on 1.7.1: a plain count stays plain, a sized group uses key=value pairs")
func workerArgumentsOn171() {
    #expect(ClusterService.workerArguments([], containerVersion: "1.7.1") == [])
    #expect(ClusterService.workerArguments([ClusterWorkerGroup(count: 0)], containerVersion: "1.7.1") == [])
    #expect(ClusterService.workerArguments([ClusterWorkerGroup(count: 2)], containerVersion: "1.7.1") == ["--workers", "2"])
    #expect(ClusterService.workerArguments(
        [ClusterWorkerGroup(count: 2, cpus: 4, memoryGiB: 8)], containerVersion: "1.7.1")
        == ["--workers", "count=2,cpus=4,memory=8GB"])
    #expect(ClusterService.workerArguments(
        [ClusterWorkerGroup(count: 1, cpus: 3)], containerVersion: "1.7.1")
        == ["--workers", "count=1,cpus=3"])
}

@Test("Worker arguments on 1.7.1: each group is its own --workers")
func workerArgumentsSeveralGroups() {
    let groups = [ClusterWorkerGroup(count: 2, cpus: 4, memoryGiB: 8), ClusterWorkerGroup(count: 1)]
    #expect(ClusterService.workerArguments(groups, containerVersion: "1.7.1")
        == ["--workers", "count=2,cpus=4,memory=8GB", "--workers", "1"])
}

@Test("Worker arguments below 1.7: only a plain total, whatever the sizes")
func workerArgumentsBelow17() {
    let groups = [ClusterWorkerGroup(count: 2, cpus: 4, memoryGiB: 8), ClusterWorkerGroup(count: 1)]
    for version in ["1.6.0", "1.6.1", nil] as [String?] {
        #expect(ClusterService.workerArguments(groups, containerVersion: version) == ["--workers", "3"], "\(version ?? "nil")")
    }
    #expect(!ClusterService.supportsWorkerSizing(containerVersion: "1.6.1"))
    #expect(ClusterService.supportsWorkerSizing(containerVersion: "1.7.0"))
    #expect(ClusterService.supportsWorkerSizing(containerVersion: "1.7.1"))
}

@MainActor
@Test("Create on 1.7.1: sized workers reach the CLI, and the control plane keeps --cpus and --memory")
func createSizedWorkers() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.7.1"

    await service.clusterService.create(
        name: "dev", cpus: 2, memory: "4GB", nodeImage: nil,
        workerGroups: [ClusterWorkerGroup(count: 2, cpus: 4, memoryGiB: 8)])

    #expect(runner.calls.contains([
        "cluster", "create", "--name", "dev", "--cpus", "2", "--memory", "4GB",
        "--workers", "count=2,cpus=4,memory=8GB",
    ]))
}

@Test("Worker group summary reads as a sentence")
func workerGroupSummary() {
    #expect(ClusterWorkerGroup.summary(of: ClusterWorkerGroup(count: 2, cpus: 4, memoryGiB: 8)) == "2 workers, 4 CPUs and 8 GB each")
    #expect(ClusterWorkerGroup.summary(of: ClusterWorkerGroup(count: 1, cpus: 1, memoryGiB: 2)) == "1 worker, 1 CPU and 2 GB")
    #expect(ClusterWorkerGroup.summary(of: ClusterWorkerGroup(count: 3)) == "3 workers")
}

// MARK: - Recreating worker sizes

@MainActor
@Test("Recreate settings on 1.7.1: worker sizes come from the live workers, one group per size")
func recreateReadsWorkerSizes() throws {
    let service = makeService()
    service.systemService.containerVersion = "1.7.1"
    let cluster = try #require(K8sCluster.group(containers: [
        try node("dev", role: "control-plane", cpus: 2, memoryGiB: 4),
        try node("dev-worker-1", role: "worker", cpus: 4, memoryGiB: 8),
        try node("dev-worker-2", role: "worker", cpus: 4, memoryGiB: 8),
        try node("dev-worker-3", role: "worker", cpus: 2, memoryGiB: 2),
    ]).first)

    let settings = service.clusterService.recreateSettings(for: cluster)

    #expect(settings.cpus == 2)
    #expect(settings.memoryGiB == 4)
    #expect(settings.workerGroups == [
        ClusterWorkerGroup(count: 2, cpus: 4, memoryGiB: 8),
        ClusterWorkerGroup(count: 1, cpus: 2, memoryGiB: 2),
    ])
    #expect(settings.workers == 3)
}

@MainActor
@Test("Recreate settings below 1.7: live workers are a plain count")
func recreateWorkerSizesBelow17() throws {
    let service = makeService()
    service.systemService.containerVersion = "1.6.1"
    let cluster = try #require(K8sCluster.group(containers: [
        try node("dev", role: "control-plane"),
        try node("dev-worker-1", role: "worker", cpus: 4, memoryGiB: 8),
        try node("dev-worker-2", role: "worker", cpus: 2, memoryGiB: 2),
    ]).first)

    #expect(service.clusterService.recreateSettings(for: cluster).workerGroups == [ClusterWorkerGroup(count: 2)])
}

@MainActor
@Test("Recreate settings on 1.7.1: with no workers left, the remembered sizes are used")
func recreateRemembersWorkerSizes() async throws {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.7.1"
    let groups = [ClusterWorkerGroup(count: 2, cpus: 4, memoryGiB: 8)]
    await service.clusterService.create(name: "dev", cpus: nil, memory: nil, nodeImage: nil, workerGroups: groups)

    let cluster = try #require(K8sCluster.group(containers: [try node("dev", role: "control-plane")]).first)
    let settings = service.clusterService.recreateSettings(for: cluster)
    #expect(settings.workerGroups == groups)

    await service.clusterService.recreate(
        name: "dev", cpus: nil, memory: nil, nodeImage: nil, cni: .kindnet, workerGroups: settings.workerGroups)
    #expect(runner.calls.filter { $0.starts(with: ["cluster", "create"]) }.last
        == ["cluster", "create", "--name", "dev", "--workers", "count=2,cpus=4,memory=8GB"])
}

// MARK: - Parsing cluster ls

@Test("cluster ls JSON: the stored configuration is read, CNI forms included")
func parseClusterList() throws {
    let clusters = try stored()
    let dev = try #require(clusters["dev"])
    #expect(dev.kubernetesVersion == "v1.35.5")
    #expect(dev.clusterCNI == .kindnet)
    #expect(dev.sharedImageStore)
    #expect(dev.workerCount == 2)
    #expect(dev.creationDate == ISO8601DateFormatter().date(from: "2026-11-09T10:15:30Z"))

    let bare = try #require(clusters["bare"])
    #expect(bare.clusterCNI == .userInstalled)
    #expect(bare.workerCount == 0)
    #expect(!bare.sharedImageStore)
}

@Test("cluster ls JSON: a manifest CNI is its path, and fractional-second dates parse")
func parseClusterListManifest() throws {
    let json = #"[{"configuration":{"name":"c","kubernetesVersion":"v1.34.11","cni":"/Users/me/cilium.yaml","nodes":[],"creationDate":"2026-11-09T10:15:30.123Z"}}]"#
    let cluster = try #require(StoredClusterConfiguration.parseList(json: json)?.first)
    #expect(cluster.clusterCNI == .manifest("/Users/me/cilium.yaml"))
    #expect(cluster.creationDate != nil)
}

@Test("cluster ls JSON: entries without a name or version are skipped, and garbage is nil")
func parseClusterListBadInput() {
    #expect(StoredClusterConfiguration.parseList(json: "[]") == [])
    #expect(StoredClusterConfiguration.parseList(json: #"[{"configuration":{"name":"x"}},{"id":"y"}]"#) == [])
    #expect(StoredClusterConfiguration.parseList(json: "") == nil)
    #expect(StoredClusterConfiguration.parseList(json: "not json") == nil)
    #expect(StoredClusterConfiguration.parseList(json: #"{"items":[]}"#) == nil)
}

@Test("cluster ls JSON: upstream's 1970 stand-in for a missing date is unknown")
func parseClusterListEpochDate() throws {
    let json = #"[{"configuration":{"name":"c","kubernetesVersion":"v1.34.11","nodes":[],"creationDate":"1970-01-01T00:00:00Z"}}]"#
    #expect(try #require(StoredClusterConfiguration.parseList(json: json)?.first).creationDate == nil)
}

// MARK: - Merging with the snapshot

@Test("Grouping with stored configurations: attached by name, node state from the containers")
func groupWithStoredConfigurations() throws {
    let clusters = K8sCluster.group(
        containers: [
            try node("dev", role: "control-plane", status: "running"),
            try node("dev-worker-1", role: "worker", status: "running"),
            try node("old", role: "control-plane,worker", status: "running"),
        ],
        stored: try stored())

    #expect(clusters.map(\.name) == ["bare", "dev", "old"])
    let dev = try #require(clusters.first { $0.name == "dev" })
    #expect(dev.stored?.kubernetesVersion == "v1.35.5")
    #expect(dev.nodes.map(\.id) == ["dev", "dev-worker-1"])
    #expect(dev.isRunning)

    // Made before 1.7: no stored configuration, so `cluster ls` doesn't list it.
    let old = try #require(clusters.first { $0.name == "old" })
    #expect(old.stored == nil)
    #expect(ClusterService.isUnlisted(old, containerVersion: "1.7.1"))
    #expect(!ClusterService.isUnlisted(old, containerVersion: "1.6.1"))
    #expect(!ClusterService.isUnlisted(dev, containerVersion: "1.7.1"))

    // Stored, but its nodes are gone: listed with none, so it can be deleted.
    let bare = try #require(clusters.first { $0.name == "bare" })
    #expect(bare.nodes.isEmpty)
    #expect(!ClusterService.isUnlisted(bare, containerVersion: "1.7.1"))
}

@Test("Subtitle: the Kubernetes version when it's stored")
func clusterSubtitle() throws {
    let clusters = K8sCluster.group(
        containers: [try node("dev", role: "control-plane"), try node("old", role: "control-plane,worker")],
        stored: try stored())
    #expect(ClusterService.subtitle(for: try #require(clusters.first { $0.name == "dev" })) == "Kubernetes v1.35.5 · 1 node")
    #expect(ClusterService.subtitle(for: try #require(clusters.first { $0.name == "old" })) == "Kubernetes cluster · 1 node")
}

@MainActor
@Test("Loading cluster ls on 1.7.1, and a failure or bad output keeps the last good list")
func loadStoredConfigurations() async {
    let runner = MockCommandRunner()
    runner.defaultResult = ProcessResult(exitCode: 0, stdout: clusterListJSON, stderr: nil)
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.7.1"

    await service.clusterService.loadStoredConfigurations()
    #expect(runner.calls.last == ["cluster", "list", "--format", "json"])
    #expect(Set(service.clusterService.storedConfigurations.keys) == ["dev", "bare"])

    runner.defaultResult = ProcessResult(exitCode: 1, stdout: nil, stderr: "XPC connection error")
    await service.clusterService.loadStoredConfigurations()
    #expect(service.clusterService.storedConfigurations.count == 2)

    runner.defaultResult = ProcessResult(exitCode: 0, stdout: "Error: something", stderr: nil)
    await service.clusterService.loadStoredConfigurations()
    #expect(service.clusterService.storedConfigurations.count == 2)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("Below 1.7 cluster ls isn't run for stored configurations")
func loadStoredConfigurationsBelow17() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)
    service.systemService.containerVersion = "1.6.1"

    await service.clusterService.loadStoredConfigurations()
    #expect(runner.calls.isEmpty)
    #expect(service.clusterService.storedConfigurations.isEmpty)
}

// MARK: - Recreating from the stored configuration

@MainActor
@Test("Recreate settings: the stored CNI and Kubernetes version win, for a cluster made outside Orchard")
func recreateFromStoredConfiguration() throws {
    let service = makeService()
    service.systemService.containerVersion = "1.7.1"
    let json = #"[{"configuration":{"name":"dev","kubernetesVersion":"v1.34.11","cni":"/Users/me/cilium.yaml","nodes":[{"name":"dev","roles":["control-plane","worker"]}]}}]"#
    let cluster = try #require(K8sCluster.group(
        containers: [try node("dev", role: "control-plane,worker")], stored: try stored(json)).first)

    let settings = service.clusterService.recreateSettings(for: cluster)

    #expect(settings.cni == .manifest("/Users/me/cilium.yaml"))
    // The node's reference has no tag; the stored version supplies it.
    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.34.11"))
}

@MainActor
@Test("Recreate settings: the stored version matches the plugin default or a listed version first")
func recreateStoredVersionMatchesKnownImages() throws {
    let service = makeService()
    service.systemService.containerVersion = "1.7.1"
    service.clusterService.pluginDefaultNodeImage = "docker.io/kindest/node:v1.35.5@sha256:ce97"
    service.clusterService.nodeImageOptions = [
        K8sNodeImageOption(version: "v1.34.11", reference: "docker.io/kindest/node:v1.34.11@sha256:a1"),
    ]
    let atDefault = try #require(K8sCluster.group(
        containers: [try node("dev", role: "control-plane")], stored: try stored()).first { $0.name == "dev" })
    #expect(service.clusterService.recreateSettings(for: atDefault).nodeImage == .pluginDefault)

    let json = #"[{"configuration":{"name":"dev","kubernetesVersion":"v1.34.11","nodes":[]}}]"#
    let listed = try #require(K8sCluster.group(
        containers: [try node("dev", role: "control-plane")], stored: try stored(json)).first)
    #expect(service.clusterService.recreateSettings(for: listed).nodeImage == .reference("docker.io/kindest/node:v1.34.11@sha256:a1"))
}

@MainActor
@Test("Recreate settings: a remembered create the stored configuration contradicts is ignored")
func recreateStoredBeatsStaleRemembered() async throws {
    let service = makeService()
    service.systemService.containerVersion = "1.7.1"
    // Made through Orchard with a manifest, then deleted and made again with the CLI.
    await service.clusterService.create(
        name: "dev", cpus: nil, memory: nil, nodeImage: "docker.io/kindest/node:v1.33.0", cni: .manifest("/Users/me/cilium.yaml"))
    let cluster = try #require(K8sCluster.group(
        containers: [try node("dev", role: "control-plane")], stored: try stored()).first { $0.name == "dev" })

    let settings = service.clusterService.recreateSettings(for: cluster)
    #expect(settings.cni == .kindnet)
    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.35.5"))
}

@MainActor
@Test("Recreate settings: a stored cluster with no nodes takes its workers and image store from the record")
func recreateStoredWithoutNodes() throws {
    let service = makeService()
    service.systemService.containerVersion = "1.7.1"
    let cluster = try #require(K8sCluster.group(containers: [], stored: try stored()).first { $0.name == "dev" })

    let settings = service.clusterService.recreateSettings(for: cluster)
    #expect(settings.workerGroups == [ClusterWorkerGroup(count: 2)])
    #expect(settings.sharedImageStore)
}

@MainActor
@Test("Recreate settings: with no stored configuration the remembered options still decide")
func recreateFallsBackToRemembered() async throws {
    let service = makeService()
    service.systemService.containerVersion = "1.7.1"
    await service.clusterService.create(
        name: "dev", cpus: nil, memory: nil, nodeImage: "docker.io/kindest/node:v1.33.0", cni: .userInstalled)
    let cluster = try #require(K8sCluster.group(containers: [try node("dev", role: "control-plane")]).first)

    let settings = service.clusterService.recreateSettings(for: cluster)
    #expect(settings.cni == .userInstalled)
    #expect(settings.nodeImage == .reference("docker.io/kindest/node:v1.33.0"))
}

@Test("Repository of a node image drops its tag and digest but keeps a registry port")
func nodeImageRepository() {
    #expect(K8sNodeImageCatalog.repository(of: "docker.io/kindest/node:v1.35.5@sha256:ce97") == "docker.io/kindest/node")
    #expect(K8sNodeImageCatalog.repository(of: "docker.io/kindest/node@sha256:ce97") == "docker.io/kindest/node")
    #expect(K8sNodeImageCatalog.repository(of: "localhost:5000/node:v1.35.5") == "localhost:5000/node")
    #expect(K8sNodeImageCatalog.repository(of: "localhost:5000/node") == "localhost:5000/node")
}
