import Testing
import Foundation
import ContainerResource
@testable import Orchard

// A container's mounts keep their kind through a recreate (#160): read with mapFilesystem,
// carried as a VolumeMapping, and sent in the spec as the same kind.

private let mixedMountsJSON = """
[
  { "type": { "virtiofs": {} }, "source": "/tmp/x", "options": [], "destination": "/x" },
  { "type": { "volume": { "name": "pgdata", "format": "ext4" } },
    "source": "/volumes/pgdata/volume.img", "options": ["ro"], "destination": "/var/lib/postgresql/data" },
  { "type": { "tmpfs": {} }, "source": "tmpfs", "options": ["size=64m"], "destination": "/cache" },
  { "type": { "block": { "format": "ext4" } }, "source": "/images/disk.img", "options": [], "destination": "/disk" }
]
"""

// MARK: - mapFilesystem

@Test("Mount mapping: a named volume keeps its name and format")
func mountMappingVolume() {
    let fs = Filesystem.volume(
        name: "pgdata", format: "ext4", source: "/volumes/pgdata/volume.img",
        destination: "/data", options: ["ro"]
    )
    let mount = mapFilesystem(fs)
    #expect(mount.type.volume == VolumeMountType(name: "pgdata", format: "ext4"))
    #expect(mount.type.block == nil)
    #expect(mount.type.virtiofs == nil)
    #expect(mount.destination == "/data")
    #expect(mount.options == ["ro"])
    #expect(ContainerMount(mount: mount, containerIds: []).mountType == "Volume (pgdata)")
}

@Test("Mount mapping: a block mount keeps its format")
func mountMappingBlock() {
    let mount = mapFilesystem(.block(format: "ext4", source: "/images/disk.img", destination: "/disk", options: []))
    #expect(mount.type.block == BlockMountType(format: "ext4"))
    #expect(mount.type.volume == nil)
    #expect(ContainerMount(mount: mount, containerIds: []).mountType == "Block (ext4)")
}

@Test("Mount mapping: tmpfs and virtiofs map as before")
func mountMappingTmpfsAndVirtiofs() {
    let tmpfs = mapFilesystem(.tmpfs(destination: "/cache", options: []))
    #expect(tmpfs.type.tmpfs != nil)
    #expect(tmpfs.type.volume == nil)
    #expect(ContainerMount(mount: tmpfs, containerIds: []).mountType == "tmpfs")

    let share = mapFilesystem(.virtiofs(source: "/tmp/x", destination: "/x", options: []))
    #expect(share.type.virtiofs != nil)
    #expect(share.type.volume == nil)
    #expect(ContainerMount(mount: share, containerIds: []).mountType == "VirtioFS")
}

@Test("A mount stored without the volume and block keys still decodes")
func mountTypeDecodesOlderJSON() throws {
    let json = #"{ "tmpfs": {} }"#
    let type = try JSONDecoder().decode(MountType.self, from: Data(json.utf8))
    #expect(type.tmpfs != nil)
    #expect(type.volume == nil)
    #expect(type.block == nil)
}

// MARK: - VolumeMapping(mount:)

@Test("A mount becomes a row of the same kind, with its options")
func volumeMappingFromMount() throws {
    let container = try makeContainer(id: "pg", status: "stopped", mountsJSON: mixedMountsJSON)
    let rows = container.configuration.mounts.map(ContainerRunConfig.VolumeMapping.init(mount:))
    #expect(rows.map(\.kind) == [.bind, .volume(name: "pgdata"), .tmpfs, .block(format: "ext4")])
    #expect(rows[1].readonly)
    #expect(rows[1].otherOptions.isEmpty)
    #expect(rows[2].otherOptions == ["size=64m"])
    #expect(rows.allSatisfy { $0.isComplete })
}

@MainActor
@Test("Edit keeps volumes, tmpfs and block mounts, not only virtiofs shares")
func editPrefillsEveryMount() throws {
    let container = try makeContainer(id: "pg", status: "stopped", mountsJSON: mixedMountsJSON)
    let config = EditContainerView.initialConfig(for: container)
    #expect(config.volumeMappings.map(\.containerPath) == ["/x", "/var/lib/postgresql/data", "/cache", "/disk"])
    #expect(config.volumeMappings.map(\.kind) == [.bind, .volume(name: "pgdata"), .tmpfs, .block(format: "ext4")])
}

// MARK: - Spec round trip

@MainActor
@Test("Removing a bind mount recreates the container with its volume, tmpfs and block mounts as they were")
func mountRemovalKeepsMountKinds() async throws {
    let backend = MockContainerBackend()
    backend.imagePlatformsResult = ["linux/arm64"]
    let service = makeService(backend: backend)
    let container = try makeContainer(id: "pg", status: "stopped", mountsJSON: mixedMountsJSON)
    let list = service.containerListService
    list.containers = [container]

    await list.deleteMounts(list.allMounts.filter { $0.mount.destination == "/x" })

    let spec = try #require(backend.createdSpecs.first)
    #expect(spec.volumes.map(\.containerPath) == ["/var/lib/postgresql/data", "/cache", "/disk"])
    #expect(spec.volumes.map(\.kind) == [.volume(name: "pgdata"), .tmpfs, .block(format: "ext4")])
    #expect(spec.volumes[0].readonly)
    #expect(spec.volumes[1].otherOptions == ["size=64m"])
    #expect(spec.volumes[2].hostPath == "/images/disk.img")
}

@MainActor
@Test("Run sends a tmpfs row, which has no host path")
func runSendsTmpfsWithoutHostPath() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    var config = ContainerRunConfig(name: "web", image: "nginx")
    config.volumeMappings = [
        .init(hostPath: "", containerPath: "/cache", kind: .tmpfs),
        .init(hostPath: "", containerPath: "/ignored"),
    ]
    await service.containerListService.runContainer(config: config)

    #expect(backend.createdSpecs.first?.volumes.map(\.kind) == [.tmpfs])
}
