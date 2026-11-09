import Foundation
import Testing
import ContainerizationOCI
@testable import Orchard

// Commit's pure parts: the version gate, the image config it writes and
// the OCI layout it archives. The XPC export and load are exercised by hand against 1.6.0.

@Test("Commit is offered from container 1.6.0")
func commitVersionGate() {
    #expect(supportsContainerCommit(containerVersion: "1.6.0"))
    #expect(supportsContainerCommit(containerVersion: "1.7.1"))
    #expect(!supportsContainerCommit(containerVersion: "1.5.0"))
    #expect(!supportsContainerCommit(containerVersion: nil))
}

@Test("The committed config starts the image the way the container started, with container labels on top")
func committedConfigMapping() {
    let config = committedImageConfig(
        sourceLabels: ["maintainer": "upstream", "version": "1"],
        containerLabels: ["version": "2", "app": "web"],
        user: "nginx",
        environment: ["PATH=/usr/bin", "MODE=prod"],
        executable: "/docker-entrypoint.sh",
        arguments: ["nginx", "-g", "daemon off;"],
        workingDirectory: "/srv",
        stopSignal: "SIGQUIT"
    )
    #expect(config.user == "nginx")
    #expect(config.env == ["PATH=/usr/bin", "MODE=prod"])
    #expect(config.entrypoint == ["/docker-entrypoint.sh"])
    #expect(config.cmd == ["nginx", "-g", "daemon off;"])
    #expect(config.workingDir == "/srv")
    #expect(config.labels == ["maintainer": "upstream", "version": "2", "app": "web"])
    #expect(config.stopSignal == "SIGQUIT")

    let bare = committedImageConfig(
        sourceLabels: nil, containerLabels: [:], user: "root", environment: [],
        executable: "/bin/sh", arguments: [], workingDirectory: "/", stopSignal: nil)
    #expect(bare.labels == [:])
    #expect(bare.stopSignal == nil)
}

@Test("The archive's OCI layout names the reference and holds one layer, the config and the manifest")
func commitArchiveLayout() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("orchard-commit-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let rootfs = directory.appendingPathComponent("rootfs.tar")
    try Data("not really a tar".utf8).write(to: rootfs)

    let platform = ContainerizationOCI.Platform(arch: "arm64", os: "linux", variant: "v8")
    let source = ContainerizationOCI.Image(
        author: "someone", architecture: "arm64", os: "linux",
        rootfs: Rootfs(type: "layers", diffIDs: []))
    let config = committedImageConfig(
        sourceLabels: nil, containerLabels: [:], user: "root", environment: ["A=1"],
        executable: "/bin/sh", arguments: ["-c", "sleep infinity"], workingDirectory: "/", stopSignal: nil)

    let archive = try makeCommitImageArchive(
        rootfs: rootfs, in: directory, reference: "docker.io/library/web:latest",
        platform: platform, sourceImage: source, config: config)
    #expect(FileManager.default.fileExists(atPath: archive.path))
    // The export is consumed once it's in the layer blob.
    #expect(!FileManager.default.fileExists(atPath: rootfs.path))

    let layout = directory.appendingPathComponent("oci-layout")
    let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: layout.appendingPathComponent("index.json")))
    let manifestDescriptor = try #require(index.manifests.first)
    #expect(index.manifests.count == 1)
    #expect(manifestDescriptor.annotations?["org.opencontainers.image.ref.name"] == "docker.io/library/web:latest")
    #expect(manifestDescriptor.annotations?["com.apple.containerization.image.name"] == "docker.io/library/web:latest")
    #expect(manifestDescriptor.platform?.architecture == "arm64")

    func blob(_ digest: String) throws -> Data {
        try Data(contentsOf: layout.appendingPathComponent("blobs/sha256/\(digest.replacingOccurrences(of: "sha256:", with: ""))"))
    }
    let manifest = try JSONDecoder().decode(Manifest.self, from: blob(manifestDescriptor.digest))
    #expect(manifest.layers.count == 1)
    #expect(try blob(manifest.layers[0].digest) == Data("not really a tar".utf8))

    let image = try JSONDecoder().decode(ContainerizationOCI.Image.self, from: blob(manifest.config.digest))
    #expect(image.author == "someone")
    #expect(image.variant == "v8")
    #expect(image.config?.cmd == ["-c", "sleep infinity"])
    #expect(image.rootfs.diffIDs == [manifest.layers[0].digest])
}
