import Testing
import Foundation
@testable import Orchard

// Managing named volumes (#161): input rules, which containers hold a volume, the service
// against the mock, Prune Volumes' plan, image VOLUME declarations, and Cmd+K.

private func volume(_ name: String, anonymous: Bool = false) -> ContainerVolume {
    ContainerVolume(
        name: name, format: "ext4", source: "/vols/\(name)/volume.img",
        creationDate: Date(timeIntervalSince1970: 0),
        labels: anonymous ? [ContainerVolume.anonymousLabel: ""] : [:], capacityBytes: nil
    )
}

private func volumeMountJSON(_ name: String) -> String {
    #"[{ "type": { "volume": { "name": "\#(name)", "format": "ext4" } }, "source": "/vols/\#(name)/volume.img", "options": [], "destination": "/data" }]"#
}

private func shareMountJSON(_ source: String) -> String {
    #"[{ "type": { "virtiofs": {} }, "source": "\#(source)", "options": [], "destination": "/data" }]"#
}

@MainActor
private func makeVolumeService(_ backend: MockContainerBackend = MockContainerBackend())
    -> (service: VolumeService, alert: AlertCenter) {
    let alert = AlertCenter()
    return (VolumeService(backend: backend, alertCenter: alert), alert)
}

// MARK: - Input

@Test("Volume name: a letter or digit, then letters, digits, _ . or -")
func volumeNameValidation() {
    #expect(InputValidation.isValidVolumeName("pgdata"))
    #expect(InputValidation.isValidVolumeName("shop_db.v2-1"))
    #expect(InputValidation.isValidVolumeName("9lives"))
    #expect(!InputValidation.isValidVolumeName(""))
    #expect(!InputValidation.isValidVolumeName("-data"))
    #expect(!InputValidation.isValidVolumeName("my data"))
    #expect(!InputValidation.isValidVolumeName("a/b"))
    #expect(!InputValidation.isValidVolumeName(String(repeating: "a", count: 256)))
}

@Test("Volume size: the CLI's binary units, at least 1 MiB")
func volumeSizeParsing() {
    let mib: UInt64 = 1_048_576
    #expect(InputValidation.volumeSizeBytes("512M") == 512 * mib)
    #expect(InputValidation.volumeSizeBytes("10G") == 10 * 1024 * mib)
    #expect(InputValidation.volumeSizeBytes("10 gb") == 10 * 1024 * mib)
    #expect(InputValidation.volumeSizeBytes("1.5GiB") == 1536 * mib)
    #expect(InputValidation.volumeSizeBytes("1t") == 1024 * 1024 * mib)
    #expect(InputValidation.volumeSizeBytes("1048576") == mib)
    #expect(InputValidation.volumeSizeBytes("1k") == nil)
    #expect(InputValidation.volumeSizeBytes("10X") == nil)
    #expect(InputValidation.volumeSizeBytes("10Gx") == nil)
    #expect(InputValidation.volumeSizeBytes("G") == nil)
    #expect(InputValidation.volumeSizeBytes("") == nil)
}

// MARK: - Usage

@Test("Volume usage: mounted by name or from inside its storage; delete names who holds it")
func volumeUsers() throws {
    let containers = [
        try makeContainer(id: "pg", status: "stopped", mountsJSON: volumeMountJSON("pgdata")),
        try makeContainer(id: "old", status: "running", mountsJSON: shareMountJSON("/vols/cache/volume.img")),
        try makeContainer(id: "web", status: "running"),
    ]
    #expect(VolumeUsage.users(of: volume("pgdata"), in: containers).map(\.configuration.id) == ["pg"])
    #expect(VolumeUsage.users(of: volume("cache"), in: containers).map(\.configuration.id) == ["old"])
    #expect(VolumeUsage.users(of: volume("logs"), in: containers).isEmpty)

    #expect(VolumeUsage.deleteBlocker([volume("logs")], containers: containers) == nil)
    let blocker = try #require(VolumeUsage.deleteBlocker([volume("logs"), volume("pgdata")], containers: containers))
    #expect(blocker.contains("pgdata is mounted by pg"))
    #expect(!blocker.contains("logs"))
}

@MainActor
@Test("Volume service: a volume a machine mounts counts as in use")
func volumeServiceCountsMachines() async throws {
    let backend = MockContainerBackend()
    backend.volumes = [volume("home"), volume("spare")]
    backend.machineContainers = [try makeContainer(id: "vm", status: "running", mountsJSON: volumeMountJSON("home"))]
    let (service, _) = makeVolumeService(backend)

    await service.load()

    #expect(service.volumes.map(\.name) == ["home", "spare"])
    #expect(service.users(of: volume("home")).map(\.configuration.id) == ["vm"])
    #expect(service.users(of: volume("spare")).isEmpty)
}

@MainActor
@Test("Volume service: sizes are read for each volume, and a failed read says so")
func volumeServiceSizes() async {
    let backend = MockContainerBackend()
    backend.volumes = [volume("a"), volume("b")]
    backend.volumeSizes = ["a": 2048]
    let (service, _) = makeVolumeService(backend)

    await service.load()

    #expect(service.sizes["a"] == .known(2048))
    #expect(service.sizes["b"] == .failed)
}

@MainActor
@Test("Volume service: create passes name, size and labels, and the list shows the volume")
func volumeServiceCreate() async throws {
    let backend = MockContainerBackend()
    let (service, _) = makeVolumeService(backend)

    let created = try await service.create(name: "pgdata", size: "10G", labels: ["app": "shop"])

    #expect(created.name == "pgdata")
    #expect(backend.createdVolumes.map(\.name) == ["pgdata"])
    #expect(backend.createdVolumes.first?.size == "10G")
    #expect(backend.createdVolumes.first?.labels == ["app": "shop"])
    #expect(service.volumes.map(\.name) == ["pgdata"])
}

@MainActor
@Test("Volume service: a delete the runtime refuses names the container now holding it")
func volumeServiceDeleteInUse() async throws {
    let backend = MockContainerBackend()
    backend.volumes = [volume("pgdata")]
    backend.containers = [try makeContainer(id: "pg", status: "running", mountsJSON: volumeMountJSON("pgdata"))]
    backend.deleteVolumeError = makeError("volume 'pgdata' is currently in use")
    let (service, alert) = makeVolumeService(backend)

    await service.delete(["pgdata"])

    let message = try #require(alert.current?.message)
    #expect(message.contains("pgdata is mounted by pg"))
}

@MainActor
@Test("Volume service: deleting drops the volume from the selection")
func volumeServiceDeleteClearsSelection() async {
    let backend = MockContainerBackend()
    backend.volumes = [volume("a"), volume("b")]
    let (service, alert) = makeVolumeService(backend)
    await service.load()
    service.selection = ["a", "b"]

    backend.volumes = [volume("b")]
    await service.delete(["a"])

    #expect(backend.deletedVolumeNames == ["a"])
    #expect(service.selection == ["b"])
    #expect(alert.current == nil)
}

// MARK: - Prune Volumes

@MainActor
@Test("Prune Volumes: the plan holds only volumes, and leaves the image store alone")
func pruneVolumesPlan() throws {
    let inventory = DiskPurgeInventory(
        containers: [try makeContainer(id: "old", status: "stopped", imageReference: "nginx:latest")],
        images: [makeImage(reference: "redis:7")],
        volumes: [volume("scratch", anonymous: true), volume("keep")],
        systemImageReferences: []
    )

    let plan = DiskPurge.preview(inventory, selection: FreeUpSpaceView.Scope.volumes.initialSelection).plan

    #expect(plan.volumeNames == ["scratch"])
    #expect(plan.imageReferences.isEmpty)
    #expect(plan.containerIDs.isEmpty)
    #expect(!plan.cleansImageStore)
}

// MARK: - Image inspect

@Test("Image config: VOLUME declarations come back sorted, and none is empty")
func imageConfigVolumeDeclarations() throws {
    let blob = #"{"architecture":"arm64","os":"linux","config":{"Env":["A=1"],"Volumes":{"/var/lib/postgresql/data":{},"/backups":{}}}}"#
    #expect(try imageConfigVolumes(from: Data(blob.utf8)) == ["/backups", "/var/lib/postgresql/data"])
    #expect(try imageConfigVolumes(from: Data(#"{"config":{"Volumes":null}}"#.utf8)) == [])
    #expect(try imageConfigVolumes(from: Data(#"{"architecture":"arm64"}"#.utf8)) == [])
}

// MARK: - Form

@Test("Mount rows: a volume row needs a volume; a tmpfs row needs only where it mounts")
func mountRowCompleteness() {
    typealias Mapping = ContainerRunConfig.VolumeMapping
    #expect(!Mapping(hostPath: "", containerPath: "/data", kind: .volume(name: "")).isComplete)
    #expect(Mapping(hostPath: "", containerPath: "/data", kind: .volume(name: "pgdata")).isComplete)
    #expect(Mapping(hostPath: "", containerPath: "/tmp", kind: .tmpfs).isComplete)
    #expect(!Mapping(hostPath: "", containerPath: "", kind: .tmpfs).isComplete)
}

// MARK: - Links

@Test("DeepLink: a volume link carries its name")
func deepLinkVolume() {
    #expect(URL(string: "orchard://volume/pgdata").flatMap(DeepLink.parse) == .volume("pgdata"))
    #expect(URL(string: "orchard://volumes").flatMap(DeepLink.parse) == .tab(.volumes))
}
