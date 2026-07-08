import Foundation
import AppKit

// MARK: - Sort Options

enum ContainerSortOption: String, CaseIterable {
    case name = "name"
    case status = "status"
    case image = "image"

    var label: String {
        switch self {
        case .name: return "Name"
        case .status: return "Status"
        case .image: return "Image"
        }
    }
}

enum ImageSortOption: String, CaseIterable {
    case name = "name"
    case tag = "tag"
    case size = "size"

    var label: String {
        switch self {
        case .name: return "Name"
        case .tag: return "Tag"
        case .size: return "Size"
        }
    }
}

// MARK: - Container Models

struct Container: Codable, Equatable {
    let status: String
    let configuration: ContainerConfiguration
    let networks: [Network]

    enum CodingKeys: String, CodingKey {
        case status
        case configuration
        case networks
    }
}

struct ContainerConfiguration: Codable, Equatable {
    let id: String
    let hostname: String?
    let runtimeHandler: String
    let initProcess: initProcess
    let mounts: [Mount]
    let platform: Platform
    let image: Image
    let rosetta: Bool
    let dns: DNS
    let resources: Resources
    let labels: [String: String]
    let publishedPorts: [PublishedPort]
    let publishedSockets: [String]?
    let ssh: Bool?
    let virtualization: Bool?
    let sysctls: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case hostname
        case runtimeHandler
        case initProcess
        case mounts
        case platform
        case image
        case rosetta
        case dns
        case resources
        case labels
        case publishedPorts
        case publishedSockets
        case ssh
        case virtualization
        case sysctls
    }
}

struct Mount: Codable, Equatable {
    let type: MountType
    let source: String
    let options: [String]
    let destination: String

    enum CodingKeys: String, CodingKey {
        case type
        case source
        case options
        case destination
    }
}

struct MountType: Codable, Equatable {
    let tmpfs: Tmpfs?
    let virtiofs: Virtiofs?

    enum CodingKeys: String, CodingKey {
        case tmpfs
        case virtiofs
    }
}

struct Tmpfs: Codable, Equatable {
}

struct Virtiofs: Codable, Equatable {
}

struct initProcess: Codable, Equatable {
    let terminal: Bool
    let environment: [String]
    let workingDirectory: String
    let arguments: [String]
    let executable: String
    let user: User
    let rlimits: [String]
    let supplementalGroups: [Int]

    enum CodingKeys: String, CodingKey {
        case terminal
        case environment
        case workingDirectory
        case arguments
        case executable
        case user
        case rlimits
        case supplementalGroups
    }
}

struct User: Codable, Equatable {
    let id: UserID?
    let raw: UserRaw?

    enum CodingKeys: String, CodingKey {
        case id
        case raw
    }
}

struct UserRaw: Codable, Equatable {
    let userString: String

    enum CodingKeys: String, CodingKey {
        case userString
    }
}

struct UserID: Codable, Equatable {
    let gid: Int
    let uid: Int

    enum CodingKeys: String, CodingKey {
        case gid
        case uid
    }
}

struct Network: Codable, Equatable {
    var gateway: String
    var hostname: String
    var network: String
    var address: String

    enum CodingKeys: String, CodingKey {
        case gateway = "ipv4Gateway"
        case hostname
        case network
        case address = "ipv4Address"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gateway = try container.decodeIfPresent(String.self, forKey: .gateway) ?? ""
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? ""
        network = try container.decodeIfPresent(String.self, forKey: .network) ?? ""
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
    }
    
    init(gateway: String = "", hostname: String = "", network: String = "", address: String = "") {
        self.gateway = gateway
        self.hostname = hostname
        self.network = network
        self.address = address
    }
}

struct Image: Codable, Equatable {
    let descriptor: ImageDescriptor
    let reference: String

    enum CodingKeys: String, CodingKey {
        case descriptor
        case reference
    }
}

struct ImageDescriptor: Codable, Equatable {
    let mediaType: String
    let digest: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case mediaType
        case digest
        case size
    }
}

struct DNS: Codable, Equatable {
    let nameservers: [String]
    let searchDomains: [String]
    let options: [String]
    let domain: String?

    enum CodingKeys: String, CodingKey {
        case nameservers
        case searchDomains
        case options
        case domain
    }
}

struct Resources: Codable, Equatable {
    let cpus: Int
    let memoryInBytes: Int

    enum CodingKeys: String, CodingKey {
        case cpus
        case memoryInBytes
    }
}

struct Platform: Codable, Equatable {
    let os: String
    let architecture: String
    let variant: String?

    enum CodingKeys: String, CodingKey {
        case os
        case architecture
        case variant
    }
}

// MARK: - Machine Models

/// A container machine — a persistent, stateful lightweight Linux VM — expressed entirely
/// in app-owned types so the machine XPC client's model types never leak past the backend.
///
/// `isDefault` is resolved by `MachineService` from the machine API's separate `getDefault()`
/// call; the snapshot itself does not carry it. `ipAddress`, `containerId`, and `startedDate`
/// are only populated while a machine is running (verified in the M0 spike).
struct Machine: Codable, Equatable, Identifiable {
    let id: String
    let status: String
    let isDefault: Bool
    let cpus: Int
    let memoryBytes: Int
    let diskSizeBytes: Int?
    /// Home directory mount mode: `rw`, `ro`, or `none`.
    let homeMount: String
    let virtualization: Bool
    let kernelPath: String?
    let imageReference: String
    let platform: Platform
    let ipAddress: String?
    let containerId: String?
    let createdDate: Date?
    let startedDate: Date?
    let initialized: Bool
    let userSetup: MachineUserSetup?

    var isRunning: Bool { status == "running" }
    var isStopped: Bool { status == "stopped" }
}

/// The host user mapped into a machine at first-boot provisioning.
struct MachineUserSetup: Codable, Equatable {
    let username: String
    let uid: Int
    let gid: Int
}

// MARK: - Local model providers (the container↔model bridge)

/// The wire API a model provider speaks. Decides which environment variables a container
/// needs so an in-container client reaches the host provider.
enum ModelAPIStyle: String, Codable, Sendable {
    case openAI
    case ollama
}

/// One turn in a chat conversation, in the shape the OpenAI/Ollama chat APIs expect.
struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var content: String
}

/// A local inference provider discovered running on the host — Ollama, LM Studio, an MLX
/// server, and so on. Orchard *manages and bridges* providers; it does not run inference
/// itself. Detected read-only in this first slice.
struct ModelProvider: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case ollama
        case lmStudio
        case mlxServer
        case custom

        var displayName: String {
            switch self {
            case .ollama: return "Ollama"
            case .lmStudio: return "LM Studio"
            case .mlxServer: return "MLX Server"
            case .custom: return "Custom"
            }
        }
    }

    let kind: Kind
    /// The loopback port the provider listens on, as seen from the host.
    let port: UInt16
    /// The wire API the provider speaks.
    let api: ModelAPIStyle
    /// Model identifiers the provider advertises, when it exposes a listing endpoint.
    var models: [String]

    /// Stable across refreshes: a provider is identified by its kind and port.
    var id: String { "\(kind.rawValue):\(port)" }

    /// The base URL reachable *from the host* (e.g. `http://127.0.0.1:11434`). Distinct
    /// from the container-reachable URL, which goes through the network gateway — see
    /// `ModelBridge`.
    var hostBaseURL: String { "http://127.0.0.1:\(port)" }
}

/// A model server Orchard started and supervises (as opposed to a `ModelProvider`, which is
/// any server merely detected running). Carries the config it was launched with plus its
/// live lifecycle state.
struct ManagedModelServer: Identifiable, Equatable, Sendable {
    enum Status: String, Sendable {
        case running
        case failed
    }

    /// Stable identity: one server per model+port. Also the log-file key.
    let id: String
    let model: String
    let host: String
    let port: UInt16
    var status: Status
    /// Absolute path to the captured stdout/stderr log.
    let logPath: String

    /// mlx_lm.server speaks the OpenAI wire API.
    var api: ModelAPIStyle { .openAI }
    /// Whether the server is bound to all interfaces, so containers can reach it.
    var reachableFromContainers: Bool { host == "0.0.0.0" }
}

struct PublishedPort: Codable, Equatable {
    let hostPort: Int
    let containerPort: Int
    let transportProtocol: String
    let hostAddress: String?

    /// Stable identity for `ForEach`: `containerPort` alone repeats when the same port is
    /// published over more than one transport (e.g. tcp + udp), which collapses rows.
    var uniqueID: String {
        "\(hostAddress ?? "")|\(hostPort)|\(containerPort)|\(transportProtocol)"
    }

    enum CodingKeys: String, CodingKey {
        case hostPort
        case containerPort
        case transportProtocol = "proto"
        case hostAddress
    }
}

// MARK: - Container Image Models

struct ContainerImage: Codable, Equatable, Identifiable {
    let descriptor: ContainerImageDescriptor
    let reference: String

    var id: String { reference }

    enum CodingKeys: String, CodingKey {
        case descriptor
        case reference
    }
}

struct ContainerImageDescriptor: Codable, Equatable {
    let digest: String
    let mediaType: String
    let size: Int
    let annotations: [String: String]?

    enum CodingKeys: String, CodingKey {
        case digest
        case mediaType
        case size
        case annotations
    }
}

// MARK: - Image Inspection Models

struct ImageInspection {
    let name: String
    let digest: String
    let mediaType: String
    let size: Int64
    let variants: [Variant]

    struct Variant {
        let platform: String
        let size: Int64
        let entrypoint: [String]?
        let cmd: [String]?
        let env: [String]?
        let workingDir: String?
        let user: String?
        let exposedPorts: [String]?
        let volumes: [String]?
    }
}

// MARK: - Mount Models

struct ContainerMount: Identifiable, Equatable {
    let id: String
    let mount: Mount
    let containerIds: [String]

    init(mount: Mount, containerIds: [String]) {
        self.mount = mount
        self.containerIds = containerIds
        // Create a unique ID based on source and destination
        self.id = "\(mount.source)->\(mount.destination)"
    }

    var mountType: String {
        if mount.type.virtiofs != nil {
            return "VirtioFS"
        } else if mount.type.tmpfs != nil {
            return "tmpfs"
        } else {
            return "Unknown"
        }
    }

    var optionsString: String {
        mount.options.joined(separator: ", ")
    }
}

// MARK: - DNS Models

struct DNSDomain: Codable, Equatable, Identifiable {
    let domain: String
    let isDefault: Bool

    var id: String { domain }

    init(domain: String, isDefault: Bool = false) {
        self.domain = domain
        self.isDefault = isDefault
    }
}

// MARK: - Kernel Models

struct KernelConfig: Codable, Equatable {
    let binary: String?
    let tar: String?
    let arch: KernelArch
    let isRecommended: Bool

    init(binary: String? = nil, tar: String? = nil, arch: KernelArch = .arm64, isRecommended: Bool = false) {
        self.binary = binary
        self.tar = tar
        self.arch = arch
        self.isRecommended = isRecommended
    }
}

enum KernelArch: String, CaseIterable, Codable {
    case amd64 = "amd64"
    case arm64 = "arm64"

    var displayName: String {
        switch self {
        case .amd64:
            return "Intel (x86_64)"
        case .arm64:
            return "Apple Silicon (ARM64)"
        }
    }
}



// MARK: - Builder Models

struct Builder: Codable, Equatable {
    let status: String
    let configuration: BuilderConfiguration
    let networks: [Network]

    enum CodingKeys: String, CodingKey {
        case status
        case configuration
        case networks
    }
}

struct BuilderConfiguration: Codable, Equatable {
    let id: String
    let image: Image
    let initProcess: initProcess
    let labels: [String: String]
    let mounts: [Mount]
    let networks: [BuilderNetwork]
    let platform: Platform
    let resources: Resources
    let rosetta: Bool
    let runtimeHandler: String
    let sysctls: [String: String]
    let dns: DNS

    enum CodingKeys: String, CodingKey {
        case id
        case image
        case initProcess
        case labels
        case mounts
        case networks
        case platform
        case resources
        case rosetta
        case runtimeHandler
        case sysctls
        case dns
    }
}

struct BuilderNetwork: Codable, Equatable {
    // Builder networks may have different structure than container networks
    // Making fields optional to handle variations in the JSON
    let gateway: String?
    let hostname: String?
    let network: String?
    let address: String?
    let name: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case gateway
        case hostname
        case network
        case address
        case name
        case id
    }
}

// MARK: - Image Pull Models

struct ImagePullProgress: Identifiable, Equatable {
    let id = UUID()
    let imageName: String
    var status: PullStatus
    var progress: Double
    var message: String

    enum PullStatus: Equatable {
        case pulling
        case completed
        case failed(String)
    }
}

// MARK: - Registry Search Models

struct RegistrySearchResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let description: String?
    let isOfficial: Bool
    let starCount: Int?

    var displayName: String {
        // Remove docker.io/library/ prefix for cleaner display
        if name.hasPrefix("docker.io/library/") {
            return String(name.dropFirst("docker.io/library/".count))
        } else if name.hasPrefix("docker.io/") {
            return String(name.dropFirst("docker.io/".count))
        }
        return name
    }
}

// MARK: - System Property Models

struct SystemProperty: Identifiable, Equatable {
    let id: String
    let type: PropertyType
    let value: String
    let description: String

    enum PropertyType: String, CaseIterable {
        case bool = "Bool"
        case string = "String"

        var displayName: String {
            return rawValue
        }
    }

    var displayValue: String {
        if type == .bool {
            return value == "true" ? "✓ Enabled" : "✗ Disabled"
        } else if value == "*undefined*" {
            return "Not set"
        }
        return value
    }

    var isUndefined: Bool {
        return value == "*undefined*"
    }
}

// MARK: - Terminal App Models

enum TerminalApp: String, CaseIterable {
    case terminal = "com.apple.Terminal"
    case iterm2 = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"

    var displayName: String {
        switch self {
        case .terminal:
            return "Terminal"
        case .iterm2:
            return "iTerm2"
        case .ghostty:
            return "Ghostty"
        }
    }

    var bundleIdentifier: String {
        return rawValue
    }

    var isInstalled: Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static var installedTerminals: [TerminalApp] {
        return allCases.filter { $0.isInstalled }
    }
}

// MARK: - Container Network Models

struct ContainerNetwork: Codable, Equatable, Identifiable {
    let id: String
    let state: String
    let config: NetworkConfig
    let status: NetworkStatus
    /// True for a host-only (`--internal`) network: reachable from the host but with no
    /// internet egress. This is the sandbox-network property the model bridge relies on —
    /// a container on it can reach a host model server yet cannot phone home. Defaults to
    /// false so it's absent-safe for older data and test fixtures.
    var isHostOnly: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case config
        case status
        case isHostOnly
    }
}

struct NetworkConfig: Codable, Equatable {
    let labels: [String: String]
    let id: String

    enum CodingKeys: String, CodingKey {
        case labels
        case id
    }
}

struct NetworkStatus: Codable, Equatable {
    let gateway: String?
    let address: String?

    enum CodingKeys: String, CodingKey {
        case gateway
        case address
    }
}

// MARK: - Container Run Configuration Models

struct ContainerRunConfig: Equatable {
    var name: String
    var image: String
    var detached: Bool = true
    var removeAfterStop: Bool = false
    var environmentVariables: [EnvironmentVariable] = []
    var portMappings: [PortMapping] = []
    var volumeMappings: [VolumeMapping] = []
    var workingDirectory: String = ""
    var commandOverride: String = ""
    var dnsDomain: String = ""
    var network: String = ""
    /// Labels to stamp on the container at creation (e.g. the sandbox marker).
    var labels: [String: String] = [:]

    struct EnvironmentVariable: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var value: String
    }

    struct PortMapping: Identifiable, Equatable {
        let id = UUID()
        var hostPort: String
        var containerPort: String
        var transportProtocol: String = "tcp"
    }

    struct VolumeMapping: Identifiable, Equatable {
        let id = UUID()
        var hostPath: String
        var containerPath: String
        var readonly: Bool = false
    }
}

// MARK: - Container Stats Models

struct ContainerStats: Codable, Equatable, Identifiable {
    let id: String
    let cpuUsageUsec: Int
    let memoryUsageBytes: Int
    let memoryLimitBytes: Int
    let blockReadBytes: Int
    let blockWriteBytes: Int
    let networkRxBytes: Int
    let networkTxBytes: Int
    let numProcesses: Int

    // Computed properties for display
    var memoryUsagePercent: Double {
        guard memoryLimitBytes > 0 else { return 0.0 }
        return Double(memoryUsageBytes) / Double(memoryLimitBytes) * 100.0
    }

    var formattedMemoryUsage: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsageBytes), countStyle: .memory)
    }

    var formattedMemoryLimit: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryLimitBytes), countStyle: .memory)
    }

    var formattedNetworkRx: String {
        ByteCountFormatter.string(fromByteCount: Int64(networkRxBytes), countStyle: .binary)
    }

    var formattedNetworkTx: String {
        ByteCountFormatter.string(fromByteCount: Int64(networkTxBytes), countStyle: .binary)
    }

    var formattedBlockRead: String {
        ByteCountFormatter.string(fromByteCount: Int64(blockReadBytes), countStyle: .binary)
    }

    var formattedBlockWrite: String {
        ByteCountFormatter.string(fromByteCount: Int64(blockWriteBytes), countStyle: .binary)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case cpuUsageUsec
        case memoryUsageBytes
        case memoryLimitBytes
        case blockReadBytes
        case blockWriteBytes
        case networkRxBytes
        case networkTxBytes
        case numProcesses
    }

    /// A copy with a different id. Used to re-key a machine's backing-container stats onto the
    /// stable machine id, so history survives the backing container id changing across reboots.
    func with(id newId: String) -> ContainerStats {
        ContainerStats(
            id: newId,
            cpuUsageUsec: cpuUsageUsec,
            memoryUsageBytes: memoryUsageBytes,
            memoryLimitBytes: memoryLimitBytes,
            blockReadBytes: blockReadBytes,
            blockWriteBytes: blockWriteBytes,
            networkRxBytes: networkRxBytes,
            networkTxBytes: networkTxBytes,
            numProcesses: numProcesses
        )
    }
}

// MARK: - System Disk Usage Models

struct SystemDiskUsage: Codable, Equatable {
    let containers: DiskUsageSection
    let images: DiskUsageSection
    let volumes: DiskUsageSection

    var totalSize: Int64 {
        containers.sizeInBytes + images.sizeInBytes + volumes.sizeInBytes
    }

    var totalReclaimable: Int64 {
        containers.reclaimable + images.reclaimable + volumes.reclaimable
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .binary)
    }

    var formattedTotalReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimable, countStyle: .binary)
    }
}

struct DiskUsageSection: Codable, Equatable {
    let active: Int
    let reclaimable: Int64
    let sizeInBytes: Int64
    let total: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .binary)
    }

    var formattedReclaimable: String {
        ByteCountFormatter.string(fromByteCount: reclaimable, countStyle: .binary)
    }

    var reclaimablePercent: Double {
        guard sizeInBytes > 0 else { return 0.0 }
        return Double(reclaimable) / Double(sizeInBytes) * 100.0
    }
}

extension String {
    /// A network address with any CIDR suffix removed, e.g. "10.0.0.2/24" → "10.0.0.2".
    /// Generic over the prefix length — the previous hard-coded "/24" strip left "/16", "/8",
    /// etc. attached to copied addresses.
    var strippingCIDRSuffix: String {
        guard let slash = firstIndex(of: "/") else { return self }
        return String(self[..<slash])
    }
}
