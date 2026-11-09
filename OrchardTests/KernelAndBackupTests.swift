import Testing
import Foundation
@testable import Orchard

// MARK: - Kernel status

/// `kernel.binaryPath` from `container system property list` on 1.7.1.
private let recommended171 = "opt/kata/share/kata-containers/vmlinux-6.18.56-208-debug"
private let kernels = "/Users/me/Library/Application Support/com.apple.container/kernels/"

@Test("Kernel: the recommended kernel for the running version is recommended")
func kernelRecommended() {
    #expect(KernelStatus.compare(installedTarget: kernels + "vmlinux-6.18.56-208-debug", recommendedBinaryPath: recommended171)
        == .recommended("vmlinux-6.18.56-208-debug"))
}

@Test("Kernel: the kernel 1.6.1 installed is out of date on 1.7.1")
func kernelOutdated() {
    #expect(KernelStatus.compare(installedTarget: kernels + "vmlinux-6.18.35-197-debug", recommendedBinaryPath: recommended171)
        == .outdated(installed: "vmlinux-6.18.35-197-debug", recommended: "vmlinux-6.18.56-208-debug"))
    // A pre-1.3.0 kernel, without the -debug suffix.
    #expect(KernelStatus.compare(installedTarget: kernels + "vmlinux-6.12.28-153", recommendedBinaryPath: recommended171)
        == .outdated(installed: "vmlinux-6.12.28-153", recommended: "vmlinux-6.18.56-208-debug"))
}

@Test("Kernel: a custom kernel stays custom and isn't flagged")
func kernelCustom() {
    #expect(KernelStatus.compare(installedTarget: kernels + "my-kernel", recommendedBinaryPath: recommended171)
        == .custom("my-kernel"))
    #expect(KernelStatus.compare(installedTarget: kernels + "vmlinux-custom-build", recommendedBinaryPath: recommended171)
        == .custom("vmlinux-custom-build"))
}

@Test("Kernel: no kernel, or no recommended one to compare with")
func kernelUnknown() {
    #expect(KernelStatus.compare(installedTarget: nil, recommendedBinaryPath: recommended171) == .notInstalled)
    #expect(KernelStatus.compare(installedTarget: kernels + "vmlinux-6.18.35-197-debug", recommendedBinaryPath: nil) == .unknown)
    #expect(KernelStatus.compare(installedTarget: kernels + "vmlinux-6.18.35-197-debug", recommendedBinaryPath: "") == .unknown)
}

@Test("Kernel: the default kernel symlink's target is read, arm64 first")
func defaultKernelTarget() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.path + "/"

    #expect(SystemService.defaultKernelTarget(in: path) == nil)
    try FileManager.default.createSymbolicLink(
        atPath: path + "default.kernel-arm64", withDestinationPath: path + "vmlinux-6.18.35-197-debug")
    #expect(SystemService.defaultKernelTarget(in: path) == path + "vmlinux-6.18.35-197-debug")
}

// MARK: - Time Machine

private func makeAppRoot(_ directories: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    for name in directories {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    return root
}

private func isExcluded(_ url: URL) throws -> Bool {
    try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
}

@Test("Time Machine: rebuildable data is reported included, then excluded, and volumes are never touched")
func backupExclusionExcludesRebuildable() throws {
    let root = try makeAppRoot(["snapshots", "containers", "volumes"])
    defer { try? FileManager.default.removeItem(at: root) }
    let exclusion = BackupExclusion(appRoot: root)

    #expect(exclusion.state() == .included(["snapshots", "containers"]))
    try exclusion.excludeRebuildable()

    #expect(exclusion.state() == .excluded)
    #expect(try isExcluded(root.appendingPathComponent("snapshots")))
    #expect(try isExcluded(root.appendingPathComponent("containers")))
    #expect(try !isExcluded(root.appendingPathComponent("volumes")))
}

@Test("Time Machine: one directory still included is reported on its own")
func backupExclusionPartial() throws {
    let root = try makeAppRoot(["snapshots", "containers"])
    defer { try? FileManager.default.removeItem(at: root) }
    var snapshots = root.appendingPathComponent("snapshots")
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try snapshots.setResourceValues(values)

    #expect(BackupExclusion(appRoot: root).state() == .included(["containers"]))
}

@Test("Time Machine: nothing to report, or create, when the directories don't exist")
func backupExclusionMissing() throws {
    let root = try makeAppRoot(["volumes"])
    defer { try? FileManager.default.removeItem(at: root) }
    let exclusion = BackupExclusion(appRoot: root)

    #expect(exclusion.state() == .missing)
    try exclusion.excludeRebuildable()
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("snapshots").path))
}

@MainActor
@Test("Time Machine: the service reads the state again after excluding")
func systemServiceExcludesRebuildable() throws {
    let root = try makeAppRoot(["snapshots", "containers"])
    defer { try? FileManager.default.removeItem(at: root) }
    let service = makeService()
    service.systemService.backupExclusion = BackupExclusion(appRoot: root)

    service.systemService.loadBackupExclusionState()
    #expect(service.systemService.backupExclusionState == .included(["snapshots", "containers"]))
    service.systemService.excludeRebuildableDataFromBackups()
    #expect(service.systemService.backupExclusionState == .excluded)
}
