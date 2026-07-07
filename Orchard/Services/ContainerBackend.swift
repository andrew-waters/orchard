import Foundation
import ContainerAPIClient
import ContainerResource
import ContainerizationOCI
import ContainerizationExtras
import ContainerPersistence

// MARK: - Boundary value types

/// System health returned by `ping()`.
struct SystemHealthInfo: Sendable {
    let apiServerVersion: String
}

/// Everything needed to create and start a container, expressed in app-owned types so
/// the backend boundary never leaks the underlying client's model types to callers.
struct ContainerCreateSpec: Sendable {
    struct Volume: Sendable {
        let hostPath: String
        let containerPath: String
        let readonly: Bool
    }
    struct Port: Sendable {
        let hostPort: UInt16
        let containerPort: UInt16
        let transportProtocol: String
    }

    let id: String
    let imageRef: String
    let environment: [String]
    let workingDirectory: String
    let commandOverride: [String]
    let volumes: [Volume]
    let publishedPorts: [Port]
    let dnsDomain: String
    let networkName: String
    let autoRemove: Bool
}

/// Combine an image's entrypoint and cmd with a user command override into the final
/// process argument vector. Override replaces cmd; entrypoint is always prefixed.
func resolveProcessArguments(imageEntrypoint: [String]?, imageCmd: [String]?, override: [String]) -> [String] {
    var processArgs: [String] = []
    if let entrypoint = imageEntrypoint, !entrypoint.isEmpty {
        processArgs = entrypoint
    }
    if !override.isEmpty {
        if processArgs.isEmpty {
            processArgs = override
        } else {
            processArgs.append(contentsOf: override)
        }
    } else if let cmd = imageCmd, !cmd.isEmpty, processArgs.isEmpty || (imageEntrypoint != nil) {
        processArgs.append(contentsOf: cmd)
    }
    return processArgs
}

// MARK: - Backend protocol

/// The container runtime surface, expressed entirely in app domain models. Mocks
/// conforming to this need no client-package imports.
protocol ContainerBackend: Sendable {
    func listContainers() async throws -> [Container]
    func stopContainer(id: String) async throws
    func killContainer(id: String, signal: Int32) async throws
    func deleteContainer(id: String, force: Bool) async throws
    func bootstrapAndStart(id: String) async throws
    func containerLogs(id: String) async throws -> [FileHandle]
    func stats(id: String) async throws -> Orchard.ContainerStats
    func createContainer(_ spec: ContainerCreateSpec) async throws
    func listImages() async throws -> [ContainerImage]
    func pullImage(reference: String) async throws
    func deleteImage(reference: String) async throws
    func inspectImage(reference: String) async throws -> ImageInspection
    func listNetworks() async throws -> [ContainerNetwork]
    func createNetwork(name: String, labels: [String: String]) async throws
    func deleteNetwork(id: String) async throws
    func ping() async throws -> SystemHealthInfo
    func diskUsage() async throws -> SystemDiskUsage
}

// MARK: - Live implementation

/// `ContainerBackend` backed by the real XPC client, translating client model types to
/// and from the app's domain models.
struct LiveContainerBackend: ContainerBackend {
    /// The persisted system configuration (registry, DNS, scheme, …) that image
    /// operations require as of container 1.1.0. Loaded from the same TOML layers the
    /// `container` CLI reads, so pulls resolve identically to the command line.
    private func loadContainerSystemConfig() async throws -> ContainerSystemConfig {
        try await ConfigurationLoader.load()
    }

    func listContainers() async throws -> [Container] {
        let snapshots = try await ContainerClient().list()
        return snapshots.map { mapContainer($0) }
    }

    func stopContainer(id: String) async throws {
        try await ContainerClient().stop(id: id)
    }

    func killContainer(id: String, signal: Int32) async throws {
        // As of container 1.1.0 the client takes the signal as a name/number string;
        // Signal(_:) on the server parses the numeric form.
        try await ContainerClient().kill(id: id, signal: String(signal))
    }

    func deleteContainer(id: String, force: Bool) async throws {
        if force {
            try await ContainerClient().delete(id: id, force: true)
        } else {
            try await ContainerClient().delete(id: id)
        }
    }

    func bootstrapAndStart(id: String) async throws {
        let stdio: [FileHandle?] = [nil, nil, nil]
        let process = try await ContainerClient().bootstrap(id: id, stdio: stdio)
        try await process.start()
    }

    func containerLogs(id: String) async throws -> [FileHandle] {
        try await ContainerClient().logs(id: id)
    }

    func stats(id: String) async throws -> Orchard.ContainerStats {
        let stats = try await ContainerClient().stats(id: id)
        return mapContainerStats(stats)
    }

    func createContainer(_ spec: ContainerCreateSpec) async throws {
        // Translate the spec's app types into the client's configuration types.
        var mounts: [Filesystem] = []
        for vol in spec.volumes {
            var options: [String] = []
            if vol.readonly { options.append("ro") }
            mounts.append(.virtiofs(source: vol.hostPath, destination: vol.containerPath, options: options))
        }

        var ports: [PublishPort] = []
        for pm in spec.publishedPorts {
            let proto = PublishProtocol(pm.transportProtocol) ?? .tcp
            ports.append(try PublishPort(
                hostAddress: try IPAddress("0.0.0.0"),
                hostPort: pm.hostPort,
                containerPort: pm.containerPort,
                proto: proto,
                count: 1
            ))
        }

        let dns: ContainerResource.ContainerConfiguration.DNSConfiguration? = {
            if spec.dnsDomain.isEmpty { return nil }
            return .init(
                nameservers: ContainerResource.ContainerConfiguration.DNSConfiguration.defaultNameservers,
                domain: spec.dnsDomain,
                searchDomains: [],
                options: []
            )
        }()

        // Fetch/unpack the image and read its OCI config.
        let systemConfig = try await loadContainerSystemConfig()
        let image = try await ClientImage.fetch(reference: spec.imageRef, containerSystemConfig: systemConfig)
        let platform = ContainerizationOCI.Platform.current
        try await image.getCreateSnapshot(platform: platform)
        let kernel = try await ClientKernel.getDefaultKernel(for: .current)
        let imageConfig = try await image.config(for: platform).config

        let mergedEnv = (imageConfig?.env ?? []) + spec.environment
        let processArgs = resolveProcessArguments(
            imageEntrypoint: imageConfig?.entrypoint,
            imageCmd: imageConfig?.cmd,
            override: spec.commandOverride
        )
        guard !processArgs.isEmpty else {
            throw OrchardError.noEntrypoint
        }

        let user: ProcessConfiguration.User = {
            if let u = imageConfig?.user, !u.isEmpty { return .raw(userString: u) }
            return .id(uid: 0, gid: 0)
        }()
        let wd = spec.workingDirectory.isEmpty ? (imageConfig?.workingDir ?? "/") : spec.workingDirectory

        let process = ProcessConfiguration(
            executable: processArgs.first!,
            arguments: Array(processArgs.dropFirst()),
            environment: mergedEnv,
            workingDirectory: wd,
            terminal: false,
            user: user
        )

        var containerConfig = ContainerResource.ContainerConfiguration(
            id: spec.id,
            image: image.description,
            process: process
        )
        containerConfig.mounts = mounts
        containerConfig.publishedPorts = ports
        containerConfig.dns = dns

        let builtinNetworkId = try await NetworkClient().builtin?.id
        let networkId = spec.networkName.isEmpty ? (builtinNetworkId ?? NetworkClient.defaultNetworkName) : spec.networkName
        containerConfig.networks = [
            AttachmentConfiguration(
                network: networkId,
                options: AttachmentOptions(hostname: spec.id, macAddress: nil, mtu: 1280)
            )
        ]

        let client = ContainerClient()
        let options = ContainerCreateOptions(autoRemove: spec.autoRemove)
        try await client.create(configuration: containerConfig, options: options, kernel: kernel)

        let stdio: [FileHandle?] = [nil, nil, nil]
        let proc = try await client.bootstrap(id: spec.id, stdio: stdio)
        try await proc.start()
    }

    func listImages() async throws -> [ContainerImage] {
        let images = try await ClientImage.list()
        return images.map { mapClientImage($0) }
    }

    func pullImage(reference: String) async throws {
        _ = try await ClientImage.pull(reference: reference, containerSystemConfig: try await loadContainerSystemConfig())
    }

    func deleteImage(reference: String) async throws {
        try await ClientImage.delete(reference: reference)
    }

    func inspectImage(reference: String) async throws -> ImageInspection {
        // container 1.1.0 removed ClientImage.details(); rebuild the inspection from the
        // OCI index (per-platform manifests) and each platform's config blob.
        let image = try await ClientImage.get(reference: reference, containerSystemConfig: try await loadContainerSystemConfig())
        let index = try await image.index()

        var variants: [ImageInspection.Variant] = []
        for manifest in index.manifests {
            guard let platform = manifest.platform else { continue }
            // Config blobs for non-local architectures may be absent; skip config
            // details rather than failing the whole inspection.
            let config = (try? await image.config(for: platform))?.config
            variants.append(ImageInspection.Variant(
                platform: "\(platform.os)/\(platform.architecture)",
                size: manifest.size,
                entrypoint: config?.entrypoint,
                cmd: config?.cmd,
                env: config?.env,
                workingDir: config?.workingDir,
                user: config?.user,
                exposedPorts: nil,
                volumes: nil
            ))
        }

        let descriptor = image.descriptor
        return ImageInspection(
            name: image.reference,
            digest: "\(descriptor.digest)",
            mediaType: descriptor.mediaType,
            size: descriptor.size,
            variants: variants
        )
    }

    func listNetworks() async throws -> [ContainerNetwork] {
        let resources = try await NetworkClient().list()
        return resources.map { mapNetworkResource($0) }
    }

    func createNetwork(name: String, labels: [String: String]) async throws {
        let config = try NetworkConfiguration(
            name: name,
            mode: .nat,
            labels: try ResourceLabels(labels),
            plugin: "container-network-vmnet"
        )
        _ = try await NetworkClient().create(configuration: config)
    }

    func deleteNetwork(id: String) async throws {
        try await NetworkClient().delete(id: id)
    }

    func ping() async throws -> SystemHealthInfo {
        let health = try await ClientHealthCheck.ping()
        return SystemHealthInfo(apiServerVersion: health.apiServerVersion)
    }

    func diskUsage() async throws -> SystemDiskUsage {
        let stats = try await ClientDiskUsage.get()
        return mapDiskUsageStats(stats)
    }
}
