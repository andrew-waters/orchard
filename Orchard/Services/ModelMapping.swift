import Foundation
import ContainerAPIClient
import ContainerResource
import ContainerizationOCI

// MARK: - ContainerSnapshot → Container

func mapContainer(_ snapshot: ContainerSnapshot) -> Container {
    Container(
        status: snapshot.status.rawValue,
        configuration: mapContainerConfiguration(snapshot.configuration),
        networks: snapshot.networks.map { mapAttachment($0) }
    )
}

// MARK: - ContainerConfiguration mapping

func mapContainerConfiguration(_ config: ContainerResource.ContainerConfiguration) -> ContainerConfiguration {
    ContainerConfiguration(
        id: config.id,
        hostname: config.networks.first?.options.hostname,
        networkName: config.networks.first?.network,
        runtimeHandler: config.runtimeHandler,
        initProcess: mapProcessConfiguration(config.initProcess),
        mounts: config.mounts.map { mapFilesystem($0) },
        platform: mapPlatform(config.platform),
        image: mapImageDescription(config.image),
        rosetta: config.rosetta,
        dns: mapDNSConfiguration(config.dns),
        resources: mapResources(config.resources),
        labels: config.labels,
        publishedPorts: config.publishedPorts.map { mapPublishPort($0) },
        publishedSockets: config.publishedSockets.map { $0.containerPath.string },
        ssh: config.ssh,
        virtualization: config.virtualization,
        sysctls: config.sysctls,
        networkAliases: mapNetworkAliases(config.networks)
    )
}

// MARK: - Network mapping

/// Each attachment's aliases by network id, leaving out attachments without any; nil when none
/// has any.
func mapNetworkAliases(_ attachments: [AttachmentConfiguration]) -> [String: [String]]? {
    var aliases: [String: [String]] = [:]
    for attachment in attachments where !attachment.options.aliases.isEmpty {
        aliases[attachment.network, default: []].append(contentsOf: attachment.options.aliases)
    }
    return aliases.isEmpty ? nil : aliases
}

func mapAttachment(_ attachment: Attachment) -> Network {
    Network(
        gateway: "\(attachment.ipv4Gateway)",
        hostname: attachment.hostname,
        network: attachment.network,
        address: "\(attachment.ipv4Address)"
    )
}

// MARK: - Process mapping

func mapProcessConfiguration(_ process: ProcessConfiguration) -> initProcess {
    let user: User
    switch process.user {
    case .id(let uid, let gid):
        user = User(id: UserID(gid: Int(gid), uid: Int(uid)), raw: nil)
    case .raw(let userString):
        user = User(id: nil, raw: UserRaw(userString: userString))
    }

    return initProcess(
        terminal: process.terminal,
        environment: process.environment,
        workingDirectory: process.workingDirectory,
        arguments: process.arguments,
        executable: process.executable,
        user: user,
        rlimits: process.rlimits.map { "\($0.limit):\($0.soft):\($0.hard)" },
        supplementalGroups: process.supplementalGroups.map { Int($0) }
    )
}

// MARK: - Mount mapping

func mapFilesystem(_ fs: Filesystem) -> Mount {
    let mountType: MountType
    switch fs.type {
    case .volume(let name, let format, let cache, let sync):
        mountType = MountType(
            tmpfs: nil, virtiofs: nil,
            volume: VolumeMountType(name: name, format: format, caching: mapMountCaching(cache, sync))
        )
    case .block(let format, let cache, let sync):
        mountType = MountType(
            tmpfs: nil, virtiofs: nil,
            block: BlockMountType(format: format, caching: mapMountCaching(cache, sync))
        )
    case .tmpfs:
        mountType = MountType(tmpfs: Tmpfs(), virtiofs: nil)
    case .virtiofs:
        mountType = MountType(tmpfs: nil, virtiofs: Virtiofs())
    }

    return Mount(
        type: mountType,
        source: fs.source,
        options: fs.options,
        destination: fs.destination
    )
}

func mapMountCaching(_ cache: Filesystem.CacheMode, _ sync: Filesystem.SyncMode) -> MountCaching {
    let mappedCache: MountCaching.Cache
    switch cache {
    case .on: mappedCache = .on
    case .off: mappedCache = .off
    case .auto: mappedCache = .auto
    }
    let mappedSync: MountCaching.Sync
    switch sync {
    case .full: mappedSync = .full
    case .fsync: mappedSync = .fsync
    case .nosync: mappedSync = .nosync
    }
    return MountCaching(cache: mappedCache, sync: mappedSync)
}

// MARK: - Platform mapping

// The variant is kept, so a container created as linux/arm/v7 is recreated as that and not as
// plain linux/arm (#147).
func mapPlatform(_ platform: ContainerizationOCI.Platform) -> Orchard.Platform {
    Orchard.Platform(
        os: "\(platform.os)",
        architecture: "\(platform.architecture)",
        variant: platform.variant
    )
}

// MARK: - Image mapping

func mapImageDescription(_ image: ImageDescription) -> Image {
    Image(
        descriptor: ImageDescriptor(
            mediaType: image.descriptor.mediaType,
            digest: "\(image.descriptor.digest)",
            size: Int(image.descriptor.size)
        ),
        reference: image.reference
    )
}

func mapClientImage(_ image: ClientImage) -> ContainerImage {
    ContainerImage(
        descriptor: ContainerImageDescriptor(
            digest: "\(image.descriptor.digest)",
            mediaType: image.descriptor.mediaType,
            size: Int(image.descriptor.size),
            annotations: nil
        ),
        reference: image.reference
    )
}

// MARK: - DNS mapping

func mapDNSConfiguration(_ dns: ContainerResource.ContainerConfiguration.DNSConfiguration?) -> DNS {
    guard let dns = dns else {
        return DNS(nameservers: [], searchDomains: [], options: [], domain: nil)
    }
    return DNS(
        nameservers: dns.nameservers,
        searchDomains: dns.searchDomains,
        options: dns.options,
        domain: dns.domain
    )
}

// MARK: - Resources mapping

func mapResources(_ resources: ContainerResource.ContainerConfiguration.Resources) -> Orchard.Resources {
    Orchard.Resources(
        cpus: resources.cpus,
        memoryInBytes: Int(resources.memoryInBytes)
    )
}

// MARK: - Port mapping

func mapPublishPort(_ port: PublishPort) -> PublishedPort {
    PublishedPort(
        hostPort: Int(port.hostPort),
        containerPort: Int(port.containerPort),
        transportProtocol: port.proto.rawValue,
        hostAddress: "\(port.hostAddress)"
    )
}

// MARK: - Stats mapping

func mapContainerStats(_ stats: ContainerResource.ContainerStats) -> Orchard.ContainerStats {
    Orchard.ContainerStats(
        id: stats.id,
        cpuUsageUsec: Int(stats.cpuUsageUsec ?? 0),
        memoryUsageBytes: Int(stats.memoryUsageBytes ?? 0),
        memoryLimitBytes: Int(stats.memoryLimitBytes ?? 0),
        blockReadBytes: Int(stats.blockReadBytes ?? 0),
        blockWriteBytes: Int(stats.blockWriteBytes ?? 0),
        networkRxBytes: Int(stats.networkRxBytes ?? 0),
        networkTxBytes: Int(stats.networkTxBytes ?? 0),
        numProcesses: Int(stats.numProcesses ?? 0)
    )
}

// MARK: - Disk usage mapping

func mapDiskUsageStats(_ stats: DiskUsageStats) -> SystemDiskUsage {
    SystemDiskUsage(
        containers: mapResourceUsage(stats.containers),
        images: mapResourceUsage(stats.images),
        volumes: mapResourceUsage(stats.volumes)
    )
}

func mapResourceUsage(_ usage: ResourceUsage) -> DiskUsageSection {
    DiskUsageSection(
        active: usage.active,
        reclaimable: Int64(usage.reclaimable),
        sizeInBytes: Int64(usage.sizeInBytes),
        total: usage.total
    )
}

// MARK: - Network resource mapping

// As of container 1.1.0 the network API replaced the created/running `NetworkState`
// enum with a single `NetworkResource` that splits persistent `configuration` from
// runtime `status`. A resource returned by `list()` always carries an assigned
// status, so it is reported as running.
func mapNetworkResource(_ resource: NetworkResource) -> ContainerNetwork {
    ContainerNetwork(
        id: resource.id,
        state: "running",
        config: NetworkConfig(labels: resource.labels.dictionary, id: resource.id),
        status: Orchard.NetworkStatus(
            gateway: "\(resource.status.ipv4Gateway)",
            address: "\(resource.status.ipv4Subnet)"
        ),
        isHostOnly: resource.configuration.mode == .hostOnly
    )
}
