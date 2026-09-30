import Foundation
import Testing
@testable import Orchard

// Tests for `K8sNodeImageCatalog`: reading the plugin default out of the CLI's help, and
// turning Docker Hub's tag list into the Create Cluster sheet's version menu.

/// Verbatim from `container k8s create --help`: the reference wraps onto its own line.
private let createHelp = """
    OPTIONS:
      --name <name>           Cluster name (default: k8s-dev) (default: k8s-dev)
      --rm, --remove          Remove the cluster container after it stops
      --node-image <node-image>
                              Node image reference (default:
                              docker.io/kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95)
                              (default:
                              docker.io/kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95)
      --cni <cni>             Optional path to a CNI manifest to apply.
    """

@Test("Plugin default: the wrapped reference is read out of the help text")
func parsesPluginDefaultFromHelp() {
    #expect(K8sNodeImageCatalog.parsePluginDefault(helpText: createHelp)
        == "docker.io/kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95")
}

@Test("Plugin default: help without the option yields nil")
func pluginDefaultMissing() {
    #expect(K8sNodeImageCatalog.parsePluginDefault(helpText: "USAGE: k8s create [--name <name>]") == nil)
}

@Test("Tag: read from name, name@digest, and a registry with a port; nil when absent")
func tagOfReference() {
    #expect(K8sNodeImageCatalog.tag(of: "docker.io/kindest/node:v1.34.11") == "v1.34.11")
    #expect(K8sNodeImageCatalog.tag(of: "docker.io/kindest/node:v1.35.5@sha256:ce97") == "v1.35.5")
    #expect(K8sNodeImageCatalog.tag(of: "localhost:5000/kindest/node:v1.33.12") == "v1.33.12")
    #expect(K8sNodeImageCatalog.tag(of: "localhost:5000/kindest/node") == nil)
    #expect(K8sNodeImageCatalog.tag(of: "docker.io/kindest/node@sha256:ce97") == nil)
    #expect(K8sNodeImageCatalog.tag(of: "docker.io/kindest/node:") == nil)
}

@Test("Options: newest patch per supported minor, newest first, pinned by digest")
func optionsFromHubTags() throws {
    // Shape of hub.docker.com/v2/repositories/kindest/node/tags, trimmed to the fields used.
    let json = """
        {"count": 9, "results": [
          {"name": "v1.37.0", "digest": "sha256:a1"},
          {"name": "v1.36.4", "digest": "sha256:b4"},
          {"name": "v1.35.8", "digest": "sha256:c8"},
          {"name": "v1.37.0-rc.1", "digest": "sha256:rc"},
          {"name": "v1.36.1", "digest": "sha256:b1"},
          {"name": "v1.35.5", "digest": "sha256:c5"},
          {"name": "v1.31.14", "digest": "sha256:d14"},
          {"name": "v1.30.13", "digest": "sha256:old"},
          {"name": "latest", "digest": "sha256:latest"},
          {"name": "v1.34.3"}
        ]}
        """
    let options = K8sNodeImageCatalog.options(from: try K8sNodeImageCatalog.parseHubTags(Data(json.utf8)))
    #expect(options.map(\.version) == ["v1.37.0", "v1.36.4", "v1.35.8", "v1.31.14"])
    #expect(options.first?.reference == "docker.io/kindest/node:v1.37.0@sha256:a1")
}

@MainActor
@Test("Load: fills the plugin default from help and the versions from the fetcher")
func loadNodeImageOptions() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, arguments in
        arguments == ["k8s", "create", "--help"]
            ? ProcessResult(exitCode: 0, stdout: createHelp, stderr: nil)
            : ProcessResult(exitCode: 0, stdout: "", stderr: nil)
    }
    let service = makeService(runner: runner)
    service.clusterService.fetchNodeImageTags = {
        [.init(name: "v1.36.4", digest: "sha256:b4")]
    }

    await service.clusterService.loadNodeImageOptions()

    #expect(service.clusterService.pluginDefaultNodeImage?.hasPrefix("docker.io/kindest/node:v1.35.5@") == true)
    #expect(service.clusterService.nodeImageOptions.map(\.version) == ["v1.36.4"])
}

@MainActor
@Test("Load: a failed fetch keeps the versions already shown")
func loadNodeImageOptionsOffline() async {
    let service = makeService()
    let kept = K8sNodeImageOption(version: "v1.36.4", reference: "docker.io/kindest/node:v1.36.4@sha256:b4")
    service.clusterService.nodeImageOptions = [kept]
    service.clusterService.fetchNodeImageTags = { throw URLError(.notConnectedToInternet) }

    await service.clusterService.loadNodeImageOptions()

    #expect(service.clusterService.nodeImageOptions == [kept])
}

@MainActor
@Test("Create: a CNI manifest is passed as --cni")
func createPassesCNI() async {
    let runner = MockCommandRunner()
    let service = makeService(runner: runner)

    await service.clusterService.create(
        name: "k8s-dev", cpus: nil, memory: nil,
        nodeImage: "docker.io/kindest/node:v1.34.11", cni: "/Users/me/cilium.yaml")

    #expect(runner.calls.contains([
        "k8s", "create", "--name", "k8s-dev",
        "--node-image", "docker.io/kindest/node:v1.34.11",
        "--cni", "/Users/me/cilium.yaml",
    ]))
}
