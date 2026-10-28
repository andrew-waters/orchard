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
    /// The network the container is configured to join. Unlike `Container.networks`, which
    /// is the live attachment and empty while the container is stopped, this survives a stop,
    /// so a stopped container still says which network it belongs to.
    let networkName: String?
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
    /// The DNS aliases on each network attachment, keyed by network id, in the runtime's
    /// normalised form (`api.test`, `.gateway.test` for a subtree). From the stored
    /// configuration, so a stopped container keeps them. Nil or empty without any.
    var networkAliases: [String: [String]]? = nil

    /// Every alias on every attachment, by network id and then in the order they were given.
    var allNetworkAliases: [String] {
        guard let networkAliases else { return [] }
        return networkAliases.keys.sorted().flatMap { networkAliases[$0] ?? [] }
    }

    /// The published ports as form rows, host address included, for a recreate to carry through.
    var publishedPortRows: [ContainerRunConfig.PortMapping] {
        publishedPorts.map {
            .init(
                hostPort: "\($0.hostPort)",
                containerPort: "\($0.containerPort)",
                transportProtocol: $0.transportProtocol,
                hostAddress: $0.hostAddress ?? "0.0.0.0"
            )
        }
    }

    /// The aliases on the first attachment, the only one Orchard creates, as form rows for a
    /// recreate to carry through.
    var primaryNetworkAliasRows: [ContainerRunConfig.NetworkAlias] {
        (networkName.flatMap { networkAliases?[$0] } ?? []).map { .init(name: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case hostname
        case networkName
        case networkAliases
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
    /// A named or anonymous volume. Optional keys, so a configuration stored before these
    /// existed still decodes.
    var volume: VolumeMountType? = nil
    /// A block device image mounted directly, as `--mount type=block` does.
    var block: BlockMountType? = nil

    enum CodingKeys: String, CodingKey {
        case tmpfs
        case virtiofs
        case volume
        case block
    }
}

struct Tmpfs: Codable, Equatable {
}

struct Virtiofs: Codable, Equatable {
}

struct VolumeMountType: Codable, Equatable {
    let name: String
    let format: String
    var caching: MountCaching? = nil
}

struct BlockMountType: Codable, Equatable {
    let format: String
    var caching: MountCaching? = nil
}

/// How the host caches and syncs a volume or block mount. Kept so a recreate mounts it the
/// same way; nil (a configuration stored before this) leaves the runtime's defaults.
struct MountCaching: Codable, Equatable, Sendable {
    enum Cache: String, Codable, Sendable { case on, off, auto }
    enum Sync: String, Codable, Sendable { case full, fsync, nosync }

    let cache: Cache
    let sync: Sync
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

/// A container machine - a persistent, stateful lightweight Linux VM - expressed entirely
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

/// The account provisioned in a machine: the host user unless chosen at creation (1.6.0).
struct MachineUserSetup: Codable, Equatable {
    let username: String
    let uid: Int
    let gid: Int
    /// The account's home directory inside the machine, separate from the home mount.
    let home: String
}

// MARK: - Local model providers (the container↔model bridge)

/// The wire API a model provider speaks. Decides which environment variables a container
/// needs so an in-container client reaches the host provider.
enum ModelAPIStyle: String, Codable, Sendable {
    case openAI
    case ollama
}

/// An address Orchard probes for a model server. Seeded from the conventional defaults the
/// first time the panel runs, then owned by the user: the host and port are editable, and
/// any endpoint can be switched off so discovery stops touching it at all (#110). A
/// detected provider is simply an endpoint that answered, so the two share an identity.
struct ModelEndpoint: Codable, Equatable, Identifiable, Sendable {
    /// Stable across edits. The host and port are an endpoint's *contents*, not its
    /// identity, so re-pointing one at a different port keeps its stored key and its place
    /// in the list. Built-ins carry a fixed slug so a defaults restore can match them up.
    let id: String
    var kind: ModelProvider.Kind
    var host: String
    var port: UInt16
    var api: ModelAPIStyle
    /// False stops discovery probing this address entirely: the escape hatch for a server
    /// that rejects every probe and would otherwise be polled for as long as Orchard runs.
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        kind: ModelProvider.Kind,
        host: String = ModelEndpoint.defaultHost,
        port: UInt16,
        api: ModelAPIStyle,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.host = host
        self.port = port
        self.api = api
        self.isEnabled = isEnabled
    }

    static let defaultHost = "127.0.0.1"

    /// Addresses that name this Mac. A server here is reached from a container through the
    /// network gateway; anything else is already routable as written.
    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "0.0.0.0"]

    static func isLoopback(_ host: String) -> Bool {
        loopbackHosts.contains(host.lowercased())
    }

    /// The listing endpoint used both to confirm liveness and to enumerate models. Derived
    /// from the wire API rather than stored, so editing an endpoint can't leave the path
    /// and the API style disagreeing.
    var listPath: String {
        switch api {
        case .openAI: return "/v1/models"
        case .ollama: return "/api/tags"
        }
    }

    /// `host:port` as a URL authority. An IPv6 literal has to be bracketed or its own
    /// colons read as the port separator: `http://::1:8080` doesn't parse at all, so an
    /// endpoint addressed that way would be skipped by every probe without a word.
    static func authority(_ host: String, port: UInt16) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// The base URL as seen from this Mac, as configured.
    var hostBaseURL: String { "http://\(Self.authority(host, port: port))" }

    /// The base URL a client actually dials. `0.0.0.0` is a bind address, not a
    /// destination - it means "every interface on this Mac" - so a client asking for it
    /// goes to loopback instead.
    var probeBaseURL: String { "http://\(Self.authority(Self.dialHost(host), port: port))" }

    static func dialHost(_ host: String) -> String {
        host == "0.0.0.0" ? "127.0.0.1" : host
    }

    /// Keychain account for this endpoint's API key. Derived from the address rather than
    /// the id so a key survives the endpoint list being reseeded.
    var secretAccount: String { "\(host):\(port)" }

    var isLoopback: Bool { Self.isLoopback(host) }

    /// ⚠ Ports are conventional defaults - revisit if they prove unreliable in the field.
    static let builtIns: [ModelEndpoint] = [
        ModelEndpoint(id: "builtin.ollama.11434", kind: .ollama, port: 11434, api: .ollama),
        ModelEndpoint(id: "builtin.lmstudio.1234", kind: .lmStudio, port: 1234, api: .openAI),
        ModelEndpoint(id: "builtin.mlx.8080", kind: .mlxServer, port: 8080, api: .openAI),
        ModelEndpoint(id: "builtin.mlx.8000", kind: .mlxServer, port: 8000, api: .openAI),
    ]

    /// The address this endpoint shipped with, when it is a built-in - the target for
    /// "restore the default". Nil for anything the user added.
    var builtInDefault: ModelEndpoint? { Self.builtIns.first { $0.id == id } }

    /// Whether the user has moved this endpoint off the address it shipped with.
    var isEdited: Bool {
        guard let original = builtInDefault else { return false }
        return original.host != host || original.port != port || original.api != api
    }

    /// Whether this endpoint earns a row of its own while nothing is answering on it. A
    /// built-in sitting on its shipped address does not: "you aren't running LM Studio"
    /// is not a thing to report, and four dead rows would be the whole panel on an idle
    /// Mac. One the user moved, or added, does - otherwise a mistyped address takes the
    /// endpoint out of the list and leaves nowhere to correct it from.
    var isUserConfigured: Bool { isEdited || builtInDefault == nil }

    var displayName: String { kind.displayName }
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

/// A local inference provider discovered running on the host - Ollama, LM Studio, an MLX
/// server, and so on. Orchard *manages and bridges* providers; it does not run inference
/// itself. Detected read-only in this first slice.
struct ModelProvider: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case ollama
        case lmStudio
        case mlxServer
        case omlx
        case custom

        var displayName: String {
            switch self {
            case .ollama: return "Ollama"
            case .lmStudio: return "LM Studio"
            case .mlxServer: return "MLX Server"
            case .omlx: return "oMLX"
            case .custom: return "Custom"
            }
        }
    }

    let kind: Kind
    /// The host the provider listens on, as configured on its endpoint. Loopback unless
    /// the user has re-pointed it.
    let host: String
    /// The port the provider listens on, as seen from this Mac.
    let port: UInt16
    /// The wire API the provider speaks.
    let api: ModelAPIStyle
    /// Model identifiers the provider advertises, when it exposes a listing endpoint.
    var models: [String]
    /// The server answered the probe with 401/403: it's running but wants an API key
    /// before it will list models or serve completions.
    var requiresAPIKey: Bool = false
    /// The configured `ModelEndpoint` this provider answered on, and the provider's own
    /// identity. Endpoint-derived rather than address-derived so editing an endpoint's
    /// host or port doesn't read as a different provider to identity-based UI state, and
    /// so `kind` being refined from the models listing (e.g. oMLX) can't flap it either.
    let endpointID: String

    init(
        kind: Kind,
        host: String = ModelEndpoint.defaultHost,
        port: UInt16,
        api: ModelAPIStyle,
        models: [String],
        requiresAPIKey: Bool = false,
        endpointID: String? = nil
    ) {
        self.kind = kind
        self.host = host
        self.port = port
        self.api = api
        self.models = models
        self.requiresAPIKey = requiresAPIKey
        // Providers built outside the configured list (fixtures, tests) fall back to the
        // address, which is unique for as long as they exist.
        self.endpointID = endpointID ?? "\(api.rawValue):\(host):\(port)"
    }

    var id: String { endpointID }

    /// The base URL reachable *from this Mac* (e.g. `http://127.0.0.1:11434`). Distinct
    /// from the container-reachable URL, which for a loopback server goes through the
    /// network gateway - see `ModelBridge`.
    var hostBaseURL: String { "http://\(ModelEndpoint.authority(host, port: port))" }

    /// Whether a container needs the gateway indirection to reach this provider.
    var isLoopback: Bool { ModelEndpoint.isLoopback(host) }
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

// MARK: - Image Size Status

enum ImageSizeStatus: Equatable {
    case loading
    case known(Int64)
    case failed
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
        if let volume = mount.type.volume {
            return "Volume (\(volume.name))"
        } else if let block = mount.type.block {
            return "Block (\(block.format))"
        } else if mount.type.virtiofs != nil {
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
    /// The IPv4 address the domain resolves to when it was created with `--localhost`: pf
    /// redirects traffic for that address to the Mac's own 127.0.0.1. Nil for a plain domain.
    let localhostRedirect: String?

    var id: String { domain }

    init(domain: String, isDefault: Bool = false, localhostRedirect: String? = nil) {
        self.domain = domain
        self.isDefault = isDefault
        self.localhostRedirect = localhostRedirect
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
    /// Byte/item counts folded from the pull's progress events; nil until the
    /// first event arrives (and always nil for a backend without progress).
    var metrics: ImagePullMetrics?

    enum PullStatus: Equatable {
        case pulling
        case completed
        case failed(String)
    }

    /// 0…1 when the total download size is known, else nil (indeterminate).
    var fraction: Double? {
        guard let metrics, metrics.totalBytes > 0 else { return nil }
        return min(1.0, Double(metrics.bytesDownloaded) / Double(metrics.totalBytes))
    }

    /// e.g. "245 MB / 512 MB · 3/8 blobs"
    var detailText: String? {
        guard let metrics, metrics.totalBytes > 0 else { return nil }
        var parts = ["\(ByteFormat.string(metrics.bytesDownloaded)) / \(ByteFormat.string(metrics.totalBytes))"]
        if metrics.totalItems > 0 {
            parts.append("\(metrics.itemsCompleted)/\(metrics.totalItems) \(metrics.itemsName)")
        }
        return parts.joined(separator: " · ")
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
    /// internet egress. This is the sandbox-network property the model bridge relies on -
    /// a container on it can reach a host model server yet cannot phone home. Derived at
    /// mapping time; excluded from `CodingKeys` so synthesised `Decodable` never requires it
    /// (it would otherwise throw `keyNotFound` on payloads/fixtures that omit it) and it
    /// simply defaults to false.
    var isHostOnly: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case config
        case status
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
    /// Label rows edited in the config form; see `effectiveLabels`.
    var labelPairs: [LabelPair] = []
    /// Resource allocation applied at create time. Defaults match the runtime's own
    /// (4 CPUs, 1 GB) so an untouched form behaves exactly as before. Memory is carried
    /// in bytes so a value that isn't a whole number of GB (e.g. a CLI-created 1.5 GB
    /// container) survives edit and recovery untouched; the form edits it in whole GB.
    var cpus: Int = ContainerRunConfig.defaultCPUs
    var memoryBytes: UInt64 = ContainerRunConfig.defaultMemoryBytes
    /// The platform to run as, `os/arch[/variant]`. Empty is Automatic: the host's when the
    /// image has it, otherwise what the image offers (`ContainerPlatform.resolve`).
    var platform: String = ""
    /// Extra DNS names for the network attachment, one per row, as entered (`api`,
    /// `.gateway`). See `effectiveNetworkAliases`.
    var networkAliases: [NetworkAlias] = []

    struct NetworkAlias: Identifiable, Equatable {
        let id = UUID()
        var name: String
    }

    /// The alias rows with whitespace trimmed and empty rows dropped.
    var effectiveNetworkAliases: [String] {
        NetworkAliases.entered(networkAliases.map(\.name))
    }

    static let bytesPerGiB: UInt64 = 1_073_741_824
    /// What a container gets when nothing asks for anything: the runtime's own defaults.
    /// Named so that the Run form and a compose file with no `deploy.resources` agree without
    /// either of them repeating the number.
    static let defaultCPUs: Int = 4
    static let defaultMemoryBytes: UInt64 = ContainerRunConfig.bytesPerGiB

    /// Whole-GB view of `memoryBytes` for the form's stepper: reads rounded to the
    /// nearest GB (never below 1), writes exact whole GB. Only a user edit goes through
    /// the setter, so an untouched non-integral value keeps its exact byte count.
    var memoryGiB: Int {
        get { max(1, Int(clamping: (memoryBytes + Self.bytesPerGiB / 2) / Self.bytesPerGiB)) }
        set { memoryBytes = UInt64(max(1, newValue)) * Self.bytesPerGiB }
    }

    struct EnvironmentVariable: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var value: String
    }

    /// Label namespaces owned by the runtime or Orchard itself; hidden from
    /// the form's label rows and carried through edits untouched.
    static let internalLabelPrefixes = ["com.apple.container.", "com.orchard."]

    /// A user-edited label row in the config form. Kept separate from `labels`
    /// (programmatic, e.g. the sandbox marker) and merged over it at create
    /// time via `effectiveLabels`.
    struct LabelPair: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var value: String
    }

    /// Programmatic labels plus the form's rows (trimmed; empty keys dropped;
    /// on a key collision the form row wins).
    var effectiveLabels: [String: String] {
        var merged = labels
        for pair in labelPairs {
            let key = pair.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            merged[key] = pair.value.trimmingCharacters(in: .whitespaces)
        }
        return merged
    }

    struct PortMapping: Identifiable, Equatable {
        let id = UUID()
        var hostPort: String
        var containerPort: String
        var transportProtocol: String = "tcp"
        /// The host interface, kept when a recreate carries a stored port through so a port
        /// published on `127.0.0.1` isn't widened. The form doesn't edit it.
        var hostAddress: String = "0.0.0.0"
    }

    struct VolumeMapping: Identifiable, Equatable {
        /// What the mount is. The form only adds bind mounts; the other kinds come from an
        /// existing container, so a recreate mounts them as they were (#160).
        enum Kind: Equatable, Sendable {
            /// A host directory shared over virtiofs. `hostPath` is the directory.
            case bind
            /// A named or anonymous volume, looked up by name at create.
            case volume(name: String)
            /// A tmpfs mount. `hostPath` is unused.
            case tmpfs
            /// A block device image. `hostPath` is the image.
            case block(format: String)
        }

        let id = UUID()
        var hostPath: String
        var containerPath: String
        var readonly: Bool = false
        var kind: Kind = .bind
        /// Mount options other than `ro`, carried through a recreate unchanged. The form
        /// doesn't edit them.
        var otherOptions: [String] = []
        /// A volume or block mount's host caching, carried through a recreate unchanged.
        var caching: MountCaching? = nil
    }
}

extension ContainerRunConfig.VolumeMapping.Kind {
    init(_ type: MountType) {
        if let volume = type.volume {
            self = .volume(name: volume.name)
        } else if let block = type.block {
            self = .block(format: block.format)
        } else if type.tmpfs != nil {
            self = .tmpfs
        } else {
            self = .bind
        }
    }

    /// The symbol for this kind of mount, the same in the Mounts tab and the form.
    var systemImage: String {
        switch self {
        case .bind: return "folder"
        case .volume: return "cylinder"
        case .tmpfs: return "memorychip"
        case .block: return "externaldrive"
        }
    }
}

extension ContainerRunConfig.VolumeMapping {
    /// The row that mounts `mount` again as it is: the same kind, destination and options.
    /// Every recreate (recovery, mount removal, Edit) builds its rows with this.
    init(mount: Mount) {
        self.init(
            hostPath: mount.source,
            containerPath: mount.destination,
            readonly: mount.options.contains("ro"),
            kind: Kind(mount.type),
            otherOptions: mount.options.filter { $0 != "ro" },
            caching: mount.type.volume?.caching ?? mount.type.block?.caching
        )
    }

    /// Whether the row has what its kind needs to be mounted. A tmpfs mount has no source.
    var isComplete: Bool {
        guard !containerPath.isEmpty else { return false }
        switch kind {
        case .tmpfs: return true
        case .volume(let name): return !name.isEmpty
        case .bind, .block: return !hostPath.isEmpty
        }
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

struct SystemDiskUsage: Codable, Equatable, Sendable {
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

struct DiskUsageSection: Codable, Equatable, Sendable {
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

/// The image store's disk usage with a chosen set of images counted as in use, worked out the
/// way `container system df` does for images. Content images share is counted once.
struct ImageDiskUsage: Equatable, Sendable {
    let total: Int
    let active: Int
    let sizeInBytes: Int64
    let reclaimable: Int64

    /// The space the images counted as in use take.
    var activeBytes: Int64 { max(0, sizeInBytes - reclaimable) }
}

/// Disk usage as the dashboard shows it. The builder and the images the runtime needs move
/// out of Containers and Images into a System share, and each section's reclaimable space is
/// what Free Up Space can remove, rather than everything the runtime calls unused.
struct DiskUsageBreakdown: Equatable, Sendable {
    let containers: DiskUsageSection
    let images: DiskUsageSection
    let volumes: DiskUsageSection
    let systemContainers: Int
    let systemImages: Int
    let systemSize: Int64

    var reclaimable: Int64 { containers.reclaimable + images.reclaimable + volumes.reclaimable }
}

// MARK: - Volume Models

/// A named or anonymous volume in the runtime's volume store (`container volume ls`).
struct ContainerVolume: Equatable, Identifiable, Sendable {
    /// The label the runtime puts on a volume it created for an anonymous mount. Mirrors
    /// upstream `VolumeConfiguration.anonymousLabel`.
    static let anonymousLabel = "com.apple.container.resource.anonymous"

    let name: String
    let format: String
    /// The volume's disk image on the host, `<volumes>/<name>/volume.img`.
    let source: String
    let creationDate: Date
    let labels: [String: String]
    /// The size the volume was created with, when one was given. Not its usage on disk.
    let capacityBytes: UInt64?

    var id: String { name }

    var isAnonymous: Bool { labels[Self.anonymousLabel] != nil }

    /// The directory holding the volume's files, or nil when the runtime gave no source.
    var storageDirectory: String? {
        source.isEmpty ? nil : (source as NSString).deletingLastPathComponent
    }
}

extension String {
    /// A network address with any CIDR suffix removed, e.g. "10.0.0.2/24" → "10.0.0.2".
    /// Generic over the prefix length - the previous hard-coded "/24" strip left "/16", "/8",
    /// etc. attached to copied addresses.
    var strippingCIDRSuffix: String {
        guard let slash = firstIndex(of: "/") else { return self }
        return String(self[..<slash])
    }
}
