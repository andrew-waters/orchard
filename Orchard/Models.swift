import Foundation

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
    let gateway: String
    let hostname: String
    let network: String
    let address: String

    enum CodingKeys: String, CodingKey {
        case gateway
        case hostname
        case network
        case address
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

struct PublishedPort: Codable, Equatable {
    let hostPort: Int
    let containerPort: Int
    let transportProtocol: String
    let hostAddress: String?

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
    let networks: [String]
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

// MARK: - Container Network Models

struct ContainerNetwork: Codable, Equatable, Identifiable {
    let id: String
    let state: String
    let config: NetworkConfig
    let status: NetworkStatus

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
    var enablePublish: Bool = false
    var publishSpec: String = ""

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
