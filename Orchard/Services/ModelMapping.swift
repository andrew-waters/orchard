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
        publishedSockets: config.publishedSockets.map { $0.containerPath.path },
        ssh: config.ssh,
        virtualization: config.virtualization,
        sysctls: config.sysctls
    )
}

// MARK: - Network mapping

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
    if fs.isTmpfs {
        mountType = MountType(tmpfs: Tmpfs(), virtiofs: nil)
    } else if fs.isVirtiofs {
        mountType = MountType(tmpfs: nil, virtiofs: Virtiofs())
    } else {
        mountType = MountType(tmpfs: nil, virtiofs: nil)
    }

    return Mount(
        type: mountType,
        source: fs.source,
        options: fs.options,
        destination: fs.destination
    )
}

// MARK: - Platform mapping

func mapPlatform(_ platform: ContainerizationOCI.Platform) -> Orchard.Platform {
    Orchard.Platform(
        os: "\(platform.os)",
        architecture: "\(platform.architecture)",
        variant: nil
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

// MARK: - Network state mapping

func mapNetworkState(_ state: NetworkState) -> ContainerNetwork {
    switch state {
    case .created(let config):
        return ContainerNetwork(
            id: config.id,
            state: "created",
            config: NetworkConfig(labels: config.labels, id: config.id),
            status: Orchard.NetworkStatus(gateway: nil, address: nil)
        )
    case .running(let config, let status):
        return ContainerNetwork(
            id: config.id,
            state: "running",
            config: NetworkConfig(labels: config.labels, id: config.id),
            status: Orchard.NetworkStatus(
                gateway: "\(status.ipv4Gateway)",
                address: "\(status.ipv4Subnet)"
            )
        )
    }
}
