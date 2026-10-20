import Foundation
import ContainerizationArchive
import ContainerizationOCI

/// The steps of a commit, reported to the sheet while it runs.
enum ContainerCommitPhase: String, Equatable, Sendable {
    case exporting = "Exporting the filesystem"
    case building = "Building the image"
    case loading = "Loading the image"
}

/// A commit in flight: the name it was asked for and the step it is on.
struct ContainerCommitProgress: Equatable {
    let reference: String
    var phase: ContainerCommitPhase
}

/// A finished commit: the name it was asked for and the reference the store gave it.
struct ContainerCommitOutcome: Equatable {
    let requested: String
    let stored: String
}

/// Whether the installed container offers commit. Orchard drives it client side over the
/// export and load routes, as `container commit` does, and follows upstream in offering it
/// from 1.6.0, the release that ships and tests it.
func supportsContainerCommit(containerVersion: String?) -> Bool {
    isContainerVersion(containerVersion, atLeast: [1, 6])
}

/// The image config a commit writes. Mirrors upstream's `OCIImageArchive` (container 1.6.0):
/// the container's init process supplies the user, environment, working directory and
/// command (as `entrypoint: [executable]`, `cmd: arguments`), the container's labels override
/// the source image's, and the stop signal is the container's. Ports, volumes and the
/// healthcheck are not carried.
func committedImageConfig(
    sourceLabels: [String: String]?,
    containerLabels: [String: String],
    user: String,
    environment: [String],
    executable: String,
    arguments: [String],
    workingDirectory: String,
    stopSignal: String?
) -> ImageConfig {
    var labels = sourceLabels ?? [:]
    labels.merge(containerLabels) { _, containerValue in containerValue }
    return ImageConfig(
        user: user,
        env: environment,
        entrypoint: [executable],
        cmd: arguments,
        workingDir: workingDirectory,
        labels: labels,
        stopSignal: stopSignal
    )
}

/// Wraps an exported rootfs tar as a one-layer OCI image archive named `reference`, ready
/// for `ClientImage.load`. A port of upstream's `OCIImageArchive.create`, which is internal
/// to `ContainerCommands`; everything it calls is public in the libraries Orchard links.
/// Writes into `directory` and returns the archive's URL.
func makeCommitImageArchive(
    rootfs: URL,
    in directory: URL,
    reference: String,
    platform: ContainerizationOCI.Platform,
    sourceImage: ContainerizationOCI.Image,
    config: ImageConfig
) throws -> URL {
    let layoutDirectory = directory.appendingPathComponent("oci-layout")
    let blobsDirectory = layoutDirectory.appendingPathComponent("blobs/sha256")
    try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
    let writer = try ContentWriter(for: blobsDirectory)

    var result = try writer.create(from: rootfs)
    let layer = Descriptor(mediaType: MediaTypes.imageLayer, digest: result.digest.digestString, size: result.size)
    let created = ISO8601DateFormatter().string(from: Date())
    let image = ContainerizationOCI.Image(
        created: created,
        author: sourceImage.author,
        architecture: platform.architecture,
        os: platform.os,
        osVersion: sourceImage.osVersion,
        osFeatures: sourceImage.osFeatures,
        variant: platform.variant,
        config: config,
        rootfs: Rootfs(type: "layers", diffIDs: [layer.digest]),
        history: [History(created: created, createdBy: "container commit")]
    )
    result = try writer.create(from: image)
    let configDescriptor = Descriptor(mediaType: MediaTypes.imageConfig, digest: result.digest.digestString, size: result.size)

    result = try writer.create(from: Manifest(config: configDescriptor, layers: [layer]))
    var manifest = Descriptor(mediaType: MediaTypes.imageManifest, digest: result.digest.digestString, size: result.size)
    manifest.annotations = [
        "org.opencontainers.image.ref.name": reference,
        "io.containerd.image.name": reference,
        "com.apple.containerization.image.name": reference,
    ]
    manifest.platform = platform

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    try encoder.encode(["imageLayoutVersion": "1.0.0"])
        .write(to: layoutDirectory.appendingPathComponent("oci-layout"), options: .atomic)
    try encoder.encode(Index(schemaVersion: 2, manifests: [manifest]))
        .write(to: layoutDirectory.appendingPathComponent("index.json"), options: .atomic)

    let archive = directory.appendingPathComponent("image.tar")
    let archiveWriter = try ArchiveWriter(format: .pax, filter: .none, file: archive)
    try archiveWriter.archiveDirectory(layoutDirectory)
    try archiveWriter.finishEncoding()
    return archive
}
