import Foundation

/// Launch argument that makes the app wire its services to an in-memory stub backend seeded
/// with fixtures — so the XCUITest smoke suite runs without a real `container` daemon.
let uiTestMockBackendArgument = "--uitest-mock-backend"

/// Launch argument that makes the stub fail `stopContainer`, so the smoke suite can exercise
/// the error-alert surface (the #54 class: a failed user action must be visible).
let uiTestFailStopArgument = "--uitest-fail-stop"

/// Distinctive seeded identifiers the UI smoke tests assert on.
enum UITestSeed {
    static let containerID = "uitest-web"
    static let stoppedContainerID = "uitest-db"
    static let imageReference = "docker.io/library/uitest-nginx:latest"
    static let networkID = "uitest-net"
}

#if DEBUG
/// A `ContainerBackend` returning fixed fixtures. Debug-only; activated solely by the
/// launch argument, never in normal use.
struct UITestBackend: ContainerBackend {
    private func container(id: String, status: String) -> Container {
        Container(
            status: status,
            configuration: ContainerConfiguration(
                id: id,
                hostname: id,
                runtimeHandler: "vm",
                initProcess: initProcess(
                    terminal: false,
                    environment: ["PATH=/usr/bin"],
                    workingDirectory: "/",
                    arguments: ["nginx", "-g", "daemon off;"],
                    executable: "/usr/sbin/nginx",
                    user: User(id: UserID(gid: 0, uid: 0), raw: nil),
                    rlimits: [],
                    supplementalGroups: []
                ),
                mounts: [],
                platform: Platform(os: "linux", architecture: "arm64", variant: nil),
                image: Image(
                    descriptor: ImageDescriptor(
                        mediaType: "application/vnd.oci.image.manifest.v1+json",
                        digest: "sha256:uitest", size: 1_000_000
                    ),
                    reference: UITestSeed.imageReference
                ),
                rosetta: false,
                dns: DNS(nameservers: [], searchDomains: [], options: [], domain: nil),
                resources: Resources(cpus: 2, memoryInBytes: 2_147_483_648),
                labels: [:],
                publishedPorts: [],
                publishedSockets: nil,
                ssh: nil,
                virtualization: nil,
                sysctls: [:]
            ),
            networks: []
        )
    }

    func listContainers() async throws -> [Container] {
        [container(id: UITestSeed.containerID, status: "running"),
         container(id: UITestSeed.stoppedContainerID, status: "stopped")]
    }
    func stopContainer(id: String) async throws {
        if ProcessInfo.processInfo.arguments.contains(uiTestFailStopArgument) {
            throw OrchardError.generic("simulated stop failure")
        }
    }
    func killContainer(id: String, signal: Int32) async throws {}
    func deleteContainer(id: String, force: Bool) async throws {}
    func bootstrapAndStart(id: String) async throws {}
    func containerLogs(id: String) async throws -> [FileHandle] { [] }
    func stats(id: String) async throws -> ContainerStats {
        ContainerStats(id: id, cpuUsageUsec: 0, memoryUsageBytes: 0, memoryLimitBytes: 0,
                       blockReadBytes: 0, blockWriteBytes: 0, networkRxBytes: 0, networkTxBytes: 0, numProcesses: 1)
    }
    func createContainer(_ spec: ContainerCreateSpec) async throws {}
    func listImages() async throws -> [ContainerImage] {
        [ContainerImage(
            descriptor: ContainerImageDescriptor(digest: "sha256:uitest",
                mediaType: "application/vnd.oci.image.index.v1+json", size: 1_000_000, annotations: nil),
            reference: UITestSeed.imageReference
        )]
    }
    func pullImage(reference: String) async throws {}
    func deleteImage(reference: String) async throws {}
    func inspectImage(reference: String) async throws -> ImageInspection {
        throw OrchardError.generic("inspect unavailable in UI-test mode")
    }
    func listNetworks() async throws -> [ContainerNetwork] {
        [ContainerNetwork(id: UITestSeed.networkID, state: "running",
                          config: NetworkConfig(labels: [:], id: UITestSeed.networkID),
                          status: NetworkStatus(gateway: "192.168.64.1", address: "192.168.64.0/24"))]
    }
    func createNetwork(name: String, subnet: String?, labels: [String: String]) async throws {}
    func deleteNetwork(id: String) async throws {}
    func ping() async throws -> SystemHealthInfo { SystemHealthInfo(apiServerVersion: "1.0.0") }
    func diskUsage() async throws -> SystemDiskUsage {
        throw OrchardError.generic("disk usage unavailable in UI-test mode")
    }
}

/// A `CommandRunner` returning benign output so CLI-backed views (builders/DNS/properties)
/// degrade quietly rather than shelling out during UI tests.
struct UITestCommandRunner: CommandRunner {
    func run(program: String, arguments: [String]) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    func runWithSudo(program: String, arguments: [String]) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
}
#endif
