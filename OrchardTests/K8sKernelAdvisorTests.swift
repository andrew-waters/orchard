import Testing
import Foundation
@testable import Orchard

// Tests for `K8sKernelAdvisor`. The version floor and the filename parsing are pure; the
// default-kernel read is exercised against a temporary directory shaped like the container
// CLI's own, so it never depends on what is installed on the machine running the suite.

// MARK: - Version parsing

@Test("Version parsing: reads major.minor out of the CLI's kernel filenames")
func parsesInstalledKernelNames() {
    let cases: [(name: String, major: Int, minor: Int)] = [
        ("vmlinux-6.12.28-153", 6, 12),          // the pre-1.0 kernel that causes the failure
        ("vmlinux-6.18.35-197-debug", 6, 18),    // the kernel container 1.3.0 recommends
        ("vmlinux-10.2.0-1", 10, 2),
    ]
    for expected in cases {
        let parsed = K8sKernelAdvisor.parseKernelVersion(fromName: expected.name)
        #expect(parsed?.major == expected.major, "major for \(expected.name)")
        #expect(parsed?.minor == expected.minor, "minor for \(expected.name)")
    }
}

@Test("Version parsing: a name carrying no version reads as nil, so a custom kernel is left alone")
func parsesUnversionedNameAsNil() {
    for name in ["vmlinux", "my-kernel", "", "vmlinux-debug"] {
        #expect(K8sKernelAdvisor.parseKernelVersion(fromName: name) == nil)
    }
}

// MARK: - The floor

@Test("Floor: kernels before 6.18 lack nftables, 6.18 and later have it")
func floorSplitsAtFirstNFTablesKernel() {
    #expect(K8sKernelAdvisor.lacksNFTables(major: 6, minor: 12))
    #expect(K8sKernelAdvisor.lacksNFTables(major: 6, minor: 17))
    #expect(K8sKernelAdvisor.lacksNFTables(major: 5, minor: 99))
    #expect(!K8sKernelAdvisor.lacksNFTables(major: 6, minor: 18))
    #expect(!K8sKernelAdvisor.lacksNFTables(major: 6, minor: 19))
    #expect(!K8sKernelAdvisor.lacksNFTables(major: 7, minor: 0))
}

// MARK: - Reading the installed default

/// A directory shaped like `~/Library/Application Support/com.apple.container`: a `kernels`
/// subdirectory whose `default.kernel-arm64` is a symlink to the versioned binary, which is
/// how the CLI records the kernel a container actually boots.
private func makeContainerHome(defaultKernel: String?) throws -> URL {
    let home = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("K8sKernelAdvisorTests-\(UUID().uuidString)")
    let kernels = home.appendingPathComponent("kernels")
    try FileManager.default.createDirectory(at: kernels, withIntermediateDirectories: true)
    if let defaultKernel {
        let binary = kernels.appendingPathComponent(defaultKernel)
        try Data().write(to: binary)
        try FileManager.default.createSymbolicLink(
            at: kernels.appendingPathComponent("default.kernel-arm64"),
            withDestinationURL: binary)
    }
    return home
}

@Test("Installed default: a pre-nftables kernel is reported by name")
func reportsOutdatedDefaultKernel() throws {
    let home = try makeContainerHome(defaultKernel: "vmlinux-6.12.28-153")
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(K8sKernelAdvisor.defaultKernelName(containerHome: home) == "vmlinux-6.12.28-153")
    #expect(K8sKernelAdvisor.outdatedDefaultKernel(containerHome: home) == "vmlinux-6.12.28-153")
}

@Test("Installed default: the recommended kernel reports nothing to warn about")
func acceptsRecommendedKernel() throws {
    let home = try makeContainerHome(defaultKernel: "vmlinux-6.18.35-197-debug")
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(K8sKernelAdvisor.defaultKernelName(containerHome: home) == "vmlinux-6.18.35-197-debug")
    #expect(K8sKernelAdvisor.outdatedDefaultKernel(containerHome: home) == nil)
}

@Test("Installed default: no kernel installed warns about nothing rather than guessing")
func silentWithoutAnInstalledKernel() throws {
    let home = try makeContainerHome(defaultKernel: nil)
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(K8sKernelAdvisor.defaultKernelName(containerHome: home) == nil)
    #expect(K8sKernelAdvisor.outdatedDefaultKernel(containerHome: home) == nil)
}

@Test("Installed default: an unversioned custom kernel is not second-guessed")
func silentForCustomKernel() throws {
    let home = try makeContainerHome(defaultKernel: "my-own-kernel")
    defer { try? FileManager.default.removeItem(at: home) }
    #expect(K8sKernelAdvisor.defaultKernelName(containerHome: home) == "my-own-kernel")
    #expect(K8sKernelAdvisor.outdatedDefaultKernel(containerHome: home) == nil)
}

// MARK: - Recognising the failure

@Test("Failure detection: the node-prep abort is recognised from the CLI's real output")
func detectsNodePrepFailure() {
    // Verbatim from `container k8s create` on 1.4.1, all of it on stderr. The last two lines
    // are the output of steps that succeeded; only the "node prep failed" phrase is accurate.
    let output = """
        Preparing node: ["id": k8s-dev]
        [2/2] Running kubeadm init [7s]
        Error: node prep failed on k8s-dev: net.ipv4.ip_forward = 1
        registry.k8s.io/pause:3.10.1
        """
    #expect(K8sKernelAdvisor.outputIndicatesNodePrepFailure(output))
}

@Test("Failure detection: unrelated failures are left to the generic CLI error")
func ignoresUnrelatedFailures() {
    for output in [
        "Error: failed to delete container (cause: \"notFound\")",
        "Error: HTTP request failed with response: 401 Unauthorized",
        "net.ipv4.ip_forward = 1",   // the misleading line alone is not the signature
        "",
    ] {
        #expect(!K8sKernelAdvisor.outputIndicatesNodePrepFailure(output))
    }
}
