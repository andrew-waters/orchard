import Testing
import Foundation
import ComposePlanner
@testable import Orchard

// Freeing disk space (#159): what counts as unused, what the preview ticks, and that the purge
// leaves alone anything in use when it runs.

private func image(_ reference: String) -> ContainerImage {
    ContainerImage(
        descriptor: ContainerImageDescriptor(
            digest: "sha256:\(reference)", mediaType: "application/vnd.oci.image.index.v1+json",
            size: 0, annotations: nil
        ),
        reference: reference
    )
}

private func volume(_ name: String, anonymous: Bool = false, labels: [String: String] = [:]) -> ContainerVolume {
    var labels = labels
    if anonymous { labels[ContainerVolume.anonymousLabel] = "" }
    return ContainerVolume(
        name: name, format: "ext4", source: "/vols/\(name)/volume.img",
        creationDate: Date(timeIntervalSince1970: 0), labels: labels, capacityBytes: nil
    )
}

private func volumeMountJSON(_ name: String) -> String {
    #"[{ "type": { "volume": { "name": "\#(name)", "format": "ext4" } }, "source": "/vols/\#(name)/volume.img", "options": [], "destination": "/data" }]"#
}

private func shareMountJSON(_ source: String) -> String {
    #"[{ "type": { "virtiofs": {} }, "source": "\#(source)", "options": [], "destination": "/data" }]"#
}

private func inventory(
    containers: [Container] = [],
    images: [ContainerImage] = [],
    volumes: [ContainerVolume] = [],
    systemImages: Set<String> = []
) -> DiskPurgeInventory {
    DiskPurgeInventory(containers: containers, images: images, volumes: volumes, systemImageReferences: systemImages)
}

// MARK: - Rules

@Test("Disk purge: an image is unused only when no container, machine or runtime need uses it")
func diskPurgeImageRules() throws {
    let inventory = inventory(
        containers: [
            try makeContainer(id: "web", status: "stopped", imageReference: "nginx:latest"),
            try makeContainer(id: "vm", status: "stopped", labels: [MachineBackingContainer.pluginLabelKey: "machine"],
                              imageReference: "ubuntu:24.04"),
        ],
        images: [image("nginx:latest"), image("ubuntu:24.04"), image("vminit:1"), image("redis:7")],
        systemImages: ["vminit:1"]
    )
    #expect(DiskPurge.candidates(in: inventory).images.map(\.reference) == ["redis:7"])
}

@Test("Disk purge: only stopped containers nothing else manages are removable")
func diskPurgeContainerRules() throws {
    let containers = [
        try makeContainer(id: "plain", status: "stopped"),
        try makeContainer(id: "running", status: "running"),
        try makeContainer(id: "machine", status: "stopped", labels: [PluginResourceMarker.pluginLabel: "machine"]),
        try makeContainer(id: "node", status: "stopped", labels: [PluginResourceMarker.pluginLabel: "cluster"]),
        try makeContainer(id: "buildkit", status: "stopped", labels: [PluginResourceMarker.roleLabel: "builder"]),
        try makeContainer(id: "db", status: "stopped", labels: [ProjectIdentity.projectLabel: "shop"]),
        try makeContainer(id: "agent", status: "stopped", labels: [SandboxMarker.sandboxLabelKey: "true"]),
    ]
    #expect(DiskPurge.candidates(in: inventory(containers: containers)).containers.map(\.configuration.id) == ["plain"])
}

@Test("Disk purge: a volume is in use when mounted by name or shared from inside its storage")
func diskPurgeVolumeRules() throws {
    let inventory = inventory(
        containers: [
            try makeContainer(id: "pg", status: "stopped", mountsJSON: volumeMountJSON("pgdata")),
            // Recreated by an Orchard before #160: the volume's disk image shared over virtiofs.
            try makeContainer(id: "old", status: "stopped", mountsJSON: shareMountJSON("/vols/cache/volume.img")),
            // A sibling path that only shares a prefix doesn't count.
            try makeContainer(id: "other", status: "running", mountsJSON: shareMountJSON("/vols/logsarchive")),
        ],
        volumes: [
            volume("pgdata"), volume("cache"), volume("logs"),
            volume("shop_db", labels: [ProjectIdentity.projectLabel: "shop"]),
        ]
    )
    #expect(DiskPurge.candidates(in: inventory).volumes.map(\.name) == ["logs"])
}

// MARK: - Preview

@Test("Disk purge preview: images start ticked, containers and volumes start off")
func diskPurgePreviewDefaults() throws {
    let inventory = inventory(
        containers: [try makeContainer(id: "old", status: "stopped", imageReference: "nginx:latest")],
        images: [image("nginx:latest"), image("redis:7")],
        volumes: [volume("scratch", anonymous: true), volume("keep")]
    )
    var selection = DiskPurgeSelection()
    var plan = DiskPurge.preview(inventory, selection: selection).plan
    #expect(plan.imageReferences == ["redis:7"])
    #expect(plan.containerIDs.isEmpty)
    #expect(plan.volumeNames.isEmpty)
    #expect(plan.cleansImageStore)

    // Turning volumes on ticks the anonymous one only.
    selection.includeVolumes = true
    plan = DiskPurge.preview(inventory, selection: selection).plan
    #expect(plan.volumeNames == ["scratch"])

    selection.setTicked(true, .volume(name: "keep"), byDefault: false)
    selection.setTicked(false, .image(reference: "redis:7"), byDefault: true)
    plan = DiskPurge.preview(inventory, selection: selection).plan
    #expect(plan.volumeNames == ["scratch", "keep"])
    #expect(plan.imageReferences.isEmpty)
}

@Test("Disk purge preview: ticking a container frees what only it used")
func diskPurgePreviewCascade() throws {
    let inventory = inventory(
        containers: [
            try makeContainer(id: "old", status: "stopped", imageReference: "nginx:latest",
                              mountsJSON: volumeMountJSON("tmp1")),
            try makeContainer(id: "web", status: "running", imageReference: "caddy:2"),
        ],
        images: [image("nginx:latest"), image("caddy:2")],
        volumes: [volume("tmp1", anonymous: true)]
    )
    var selection = DiskPurgeSelection()
    selection.includeContainers = true
    selection.includeVolumes = true
    #expect(DiskPurge.preview(inventory, selection: selection).plan.imageReferences.isEmpty)

    selection.setTicked(true, .container(id: "old"), byDefault: false)
    let preview = DiskPurge.preview(inventory, selection: selection)
    #expect(preview.plan.containerIDs == ["old"])
    #expect(preview.plan.imageReferences == ["nginx:latest"])
    #expect(preview.plan.volumeNames == ["tmp1"])
    #expect(preview.freedByContainers == [.image(reference: "nginx:latest"), .volume(name: "tmp1")])

    // With the containers section off, the tick doesn't count.
    selection.includeContainers = false
    #expect(DiskPurge.preview(inventory, selection: selection).plan.imageReferences.isEmpty)
}

// MARK: - Purge

@Test("Disk purge: removes the plan and adds up what it freed")
func diskPurgeRemoves() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "old", status: "stopped", imageReference: "nginx:latest")]
    backend.images = [image("nginx:latest")]
    backend.volumes = [volume("scratch")]
    backend.containerSizes = ["old": 100]
    backend.volumeSizes = ["scratch": 20]
    backend.orphanedBlobBytes = 3

    let plan = DiskPurgePlan(
        containerIDs: ["old"], imageReferences: ["nginx:latest"], volumeNames: ["scratch"], cleansImageStore: true
    )
    let result = try await DiskPurge.purge(plan, backend: backend)

    #expect(backend.deletedContainers.map(\.id) == ["old"])
    #expect(backend.deletedImageReferences == ["nginx:latest"])
    #expect(backend.deletedVolumeNames == ["scratch"])
    #expect(backend.cleanUpCount == 1)
    #expect(result.freedBytes == 123)
    #expect(result.removed.count == 3)
    #expect(result.skipped.isEmpty)
    #expect(result.failures.isEmpty)
}

@Test("Disk purge: anything in use by the time it runs is left alone")
func diskPurgeRechecks() async throws {
    let backend = MockContainerBackend()
    backend.images = [image("redis:7")]
    backend.volumes = [volume("cache")]
    // Since the preview, a container started from the image with the volume mounted, and a
    // machine started from the other.
    backend.containers = [try makeContainer(id: "new", status: "running", imageReference: "redis:7",
                                            mountsJSON: volumeMountJSON("cache"))]
    backend.machineContainers = [try makeContainer(id: "vm", status: "stopped",
                                                   labels: [PluginResourceMarker.pluginLabel: "machine"],
                                                   imageReference: "ubuntu:24.04")]
    backend.images.append(image("ubuntu:24.04"))

    let plan = DiskPurgePlan(
        containerIDs: ["new"], imageReferences: ["redis:7", "ubuntu:24.04"], volumeNames: ["cache"]
    )
    let result = try await DiskPurge.purge(plan, backend: backend)

    #expect(backend.deletedContainers.isEmpty)
    #expect(backend.deletedImageReferences.isEmpty)
    #expect(backend.deletedVolumeNames.isEmpty)
    #expect(Set(result.skipped) == [
        .init(item: .container(id: "new"), reason: .nowInUse),
        .init(item: .image(reference: "redis:7"), reason: .nowInUse),
        .init(item: .image(reference: "ubuntu:24.04"), reason: .nowInUse),
        .init(item: .volume(name: "cache"), reason: .nowInUse),
    ])
}

@Test("Disk purge: anything removed some other way since the preview is reported as already gone")
func diskPurgeAlreadyGone() async throws {
    let backend = MockContainerBackend()
    backend.images = [image("redis:7")]

    let plan = DiskPurgePlan(
        containerIDs: ["old"], imageReferences: ["redis:7", "nginx:latest"], volumeNames: ["scratch"]
    )
    let result = try await DiskPurge.purge(plan, backend: backend)

    #expect(backend.deletedImageReferences == ["redis:7"])
    #expect(Set(result.skipped) == [
        .init(item: .container(id: "old"), reason: .alreadyGone),
        .init(item: .image(reference: "nginx:latest"), reason: .alreadyGone),
        .init(item: .volume(name: "scratch"), reason: .alreadyGone),
    ])
}

@Test("Disk purge: a container that fails to go keeps its image and volumes")
func diskPurgeContainerFailureKeepsWhatItUses() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "old", status: "stopped", imageReference: "nginx:latest",
                                            mountsJSON: volumeMountJSON("tmp1"))]
    backend.images = [image("nginx:latest")]
    backend.volumes = [volume("tmp1", anonymous: true)]
    backend.deleteContainerError = makeError("busy")

    let plan = DiskPurgePlan(containerIDs: ["old"], imageReferences: ["nginx:latest"], volumeNames: ["tmp1"])
    let result = try await DiskPurge.purge(plan, backend: backend)

    #expect(backend.deletedImageReferences.isEmpty)
    #expect(backend.deletedVolumeNames.isEmpty)
    #expect(result.failures.map(\.item) == [.container(id: "old")])
    #expect(Set(result.skipped) == [
        .init(item: .image(reference: "nginx:latest"), reason: .keptForFailedContainer),
        .init(item: .volume(name: "tmp1"), reason: .keptForFailedContainer),
    ])
    // Said as kept for the container, not as newly in use.
    #expect(DiskPurgeResult.SkipReason.keptForFailedContainer.title == "Kept: a container that couldn't be removed uses it")
}

@MainActor
@Test("Disk purge service: loads the inventory with sizes, purges and refreshes")
func diskPurgeServiceLoadAndPurge() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "old", status: "stopped")]
    backend.volumes = [volume("scratch", anonymous: true)]
    backend.containerSizes = ["old": 7]
    backend.volumeSizes = ["scratch": 9]
    let service = DiskPurgeService(backend: backend)
    var refreshed = 0
    service.onPurged = { refreshed += 1 }

    await service.load()
    #expect(service.phase == .ready)
    #expect(service.containerSizes == ["old": .known(7)])
    #expect(service.volumeSizes == ["scratch": .known(9)])

    await service.purge(DiskPurgePlan(volumeNames: ["scratch"]))
    #expect(service.phase == .finished(DiskPurgeResult(removed: [.volume(name: "scratch")], freedBytes: 9)))
    #expect(refreshed == 1)

    // Opened again, the sheet starts from loading, not from this result.
    service.reset()
    #expect(service.phase == .loading)
    #expect(service.inventory == nil)
    #expect(service.volumeSizes.isEmpty)
}

@MainActor
@Test("Disk purge service: a size the runtime can't read is failed, not still measuring")
func diskPurgeServiceFailedSize() async throws {
    let backend = MockContainerBackend()
    backend.containers = [try makeContainer(id: "old", status: "stopped")]
    backend.volumes = [volume("scratch")]
    let service = DiskPurgeService(backend: backend)

    await service.load()
    #expect(service.containerSizes == ["old": .failed])
    #expect(service.volumeSizes == ["scratch": .failed])
}
