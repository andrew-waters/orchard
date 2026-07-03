import Foundation
import SwiftUI

enum SystemStatus {
    case unknown
    case stopped
    case running
    case newerVersion
    case unsupportedVersion

    var color: Color {
        switch self {
        case .unknown, .stopped: return .gray
        case .running: return .green
        case .newerVersion: return .yellow
        case .unsupportedVersion: return .red
        }
    }

    var text: String {
        switch self {
        case .unknown: return "unknown"
        case .stopped: return "stopped"
        case .running: return "running"
        case .newerVersion: return "version not yet supported"
        case .unsupportedVersion: return "unsupported version"
        }
    }
}

/// Owns container-system state: health/version, kernel, system properties, disk usage,
/// and the start/stop/restart lifecycle.
@MainActor
final class SystemService: ObservableObject {
    @Published var systemStatus: SystemStatus = .unknown
    @Published var systemStatusError: String?
    @Published var systemStatusVersionOverride: Bool = false
    @Published var isSystemLoading = false
    @Published var containerVersion: String?
    @Published var parsedContainerVersion: String?
    @Published var kernelConfig: KernelConfig = KernelConfig()
    @Published var isKernelLoading = false
    @Published var systemProperties: [SystemProperty] = []
    @Published var isSystemPropertiesLoading = false
    @Published var systemDiskUsage: SystemDiskUsage?
    @Published var isSystemDiskUsageLoading = false

    private let backend: ContainerBackend
    private let runner: CommandRunner
    private let settings: SettingsStore
    private let alertCenter: AlertCenter

    /// Refresh the container list after the system starts. Set by the owner.
    var onSystemStarted: () async -> Void = {}
    /// Clear the container list after the system stops. Set by the owner.
    var onSystemStopped: () -> Void = {}
    /// Optimistically mark the DNS default domain. Set by the owner.
    var markDNSDefault: @MainActor (String) -> Void = { _ in }
    /// Reload DNS domains. Set by the owner.
    var reloadDNS: () async -> Void = {}

    init(backend: ContainerBackend, runner: CommandRunner, settings: SettingsStore, alertCenter: AlertCenter) {
        self.backend = backend
        self.runner = runner
        self.settings = settings
        self.alertCenter = alertCenter
    }

    func checkSystemStatus() async {
        do {
            let health = try await backend.ping()
            self.containerVersion = health.apiServerVersion
            self.parsedContainerVersion = health.apiServerVersion
            self.systemStatus = .running
            self.systemStatusError = nil
        } catch {
            self.containerVersion = nil
            self.parsedContainerVersion = nil
            self.systemStatus = .stopped
            self.systemStatusError = "\(type(of: error)): \(String(describing: error))"
        }
    }

    func checkSystemStatusIgnoreVersion() async {
        systemStatusVersionOverride = true
        await checkSystemStatus()
    }

    func checkContainerVersion() async {
        await checkSystemStatus()
    }

    func startSystem() async {
        isSystemLoading = true
        alertCenter.dismiss()

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "start"])
            isSystemLoading = false
            if result.failed {
                alertCenter.error(result.stderr ?? "Failed to start system")
                await checkSystemStatus()   // don't assume .running — re-derive
                return
            }
            systemStatus = .running
            Log.containers.debug("Container system started successfully")
            await onSystemStarted()
        } catch {
            alertCenter.error("Failed to start system: \(error.localizedDescription)")
            isSystemLoading = false
            await checkSystemStatus()
            Log.containers.error("Error starting system: \(error.localizedDescription)")
        }
    }

    func stopSystem() async {
        isSystemLoading = true
        alertCenter.dismiss()

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "stop"])
            isSystemLoading = false
            if result.failed {
                alertCenter.error(result.stderr ?? "Failed to stop system")
                await checkSystemStatus()   // don't assume .stopped — re-derive
                return
            }
            systemStatus = .stopped
            onSystemStopped()
            Log.containers.debug("Container system stopped successfully")
        } catch {
            alertCenter.error("Failed to stop system: \(error.localizedDescription)")
            isSystemLoading = false
            await checkSystemStatus()
            Log.containers.error("Error stopping system: \(error.localizedDescription)")
        }
    }

    func restartSystem() async {
        isSystemLoading = true
        alertCenter.dismiss()

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "restart"])
            isSystemLoading = false
            if result.failed {
                alertCenter.error(result.stderr ?? "Failed to restart system")
                await checkSystemStatus()   // don't assume .running — re-derive
                return
            }
            systemStatus = .running
            Log.containers.debug("Container system restarted successfully")
            await onSystemStarted()
        } catch {
            alertCenter.error("Failed to restart system: \(error.localizedDescription)")
            isSystemLoading = false
            await checkSystemStatus()
            Log.containers.error("Error restarting system: \(error.localizedDescription)")
        }
    }

    // MARK: - Disk usage

    func loadSystemDiskUsage(showLoading: Bool = true) async {
        if showLoading {
            isSystemDiskUsageLoading = true
        }

        do {
            let diskUsage = try await backend.diskUsage()
            self.systemDiskUsage = diskUsage
            self.isSystemDiskUsageLoading = false
        } catch {
            self.systemDiskUsage = nil
            self.isSystemDiskUsageLoading = false
            // Runs on the 1s stats poll — only a user-initiated load may alert.
            self.alertCenter.error("Failed to load system disk usage: \(error.localizedDescription)",
                                   source: showLoading ? .user : .background)
        }
    }

    // MARK: - Kernel

    func loadKernelConfig() async {
        isKernelLoading = true

        do {
            let kernelsDir = NSHomeDirectory() + "/Library/Application Support/com.apple.container/kernels/"
            let fileManager = FileManager.default

            let arm64KernelPath = kernelsDir + "default.kernel-arm64"
            let amd64KernelPath = kernelsDir + "default.kernel-amd64"

            var kernelPath: String?
            var arch: KernelArch = .arm64

            if fileManager.fileExists(atPath: arm64KernelPath) {
                kernelPath = arm64KernelPath
                arch = .arm64
            } else if fileManager.fileExists(atPath: amd64KernelPath) {
                kernelPath = amd64KernelPath
                arch = .amd64
            }

            if let kernelPath = kernelPath {
                let resolvedPath = try fileManager.destinationOfSymbolicLink(atPath: kernelPath)
                if resolvedPath.contains("vmlinux-") {
                    self.kernelConfig = KernelConfig(arch: arch, isRecommended: true)
                } else {
                    self.kernelConfig = KernelConfig(binary: resolvedPath, arch: arch)
                }
                self.isKernelLoading = false
            } else {
                self.kernelConfig = KernelConfig()
                self.isKernelLoading = false
            }
        } catch {
            self.kernelConfig = KernelConfig()
            self.isKernelLoading = false
        }
    }

    func setRecommendedKernel() async {
        isKernelLoading = true

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "kernel", "set", "--recommended"])

            if !result.failed {
                self.kernelConfig = KernelConfig(isRecommended: true)
                self.isKernelLoading = false
            } else {
                let errorOutput = result.stderr ?? ""
                // Treat "already installed" as success.
                if OrchardError.isAlreadyExistsError(errorOutput) {
                    self.kernelConfig = KernelConfig(isRecommended: true)
                    self.isKernelLoading = false
                } else {
                    self.alertCenter.error(result.stderr ?? "Failed to set recommended kernel")
                    self.isKernelLoading = false
                }
            }
        } catch {
            self.alertCenter.error("Failed to set recommended kernel: \(error.localizedDescription)")
            self.isKernelLoading = false
        }
    }

    func setCustomKernel(binary: String?, tar: String?, arch: KernelArch) async {
        isKernelLoading = true

        do {
            var arguments = ["system", "kernel", "set", "--arch", arch.rawValue]
            if let binary = binary, !binary.isEmpty {
                arguments.append(contentsOf: ["--binary", binary])
            }
            if let tar = tar, !tar.isEmpty {
                arguments.append(contentsOf: ["--tar", tar])
            }

            let result = try await runner.run(program: settings.safeContainerBinaryPath(), arguments: arguments)

            if !result.failed {
                self.kernelConfig = KernelConfig(binary: binary, tar: tar, arch: arch, isRecommended: false)
                self.isKernelLoading = false
            } else {
                self.alertCenter.error(result.stderr ?? "Failed to set custom kernel")
                self.isKernelLoading = false
            }
        } catch {
            self.alertCenter.error("Failed to set custom kernel: \(error.localizedDescription)")
            self.isKernelLoading = false
        }
    }

    // MARK: - System properties

    func loadSystemProperties(showLoading: Bool = true) async {
        if showLoading {
            isSystemPropertiesLoading = true
            alertCenter.dismiss()
        }

        var result: ProcessResult
        do {
            result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "property", "list", "--format=json"])
        } catch {
            result = ProcessResult(exitCode: -1, stdout: nil, stderr: error.localizedDescription)
        }

        if result.failed {
            // Reached every 5s via the DNS refresh — only alert on a user-initiated load.
            alertCenter.error(result.stderr ?? "Failed to load system properties",
                              source: showLoading ? .user : .background)
            isSystemPropertiesLoading = false
            return
        }

        guard let output = result.stdout else {
            systemProperties = []
            isSystemPropertiesLoading = false
            return
        }

        systemProperties = parseSystemProperties(json: output)
        isSystemPropertiesLoading = false
    }

    /// Optimistically record `value` for the `dns.domain` property.
    func setDNSDomainPropertyOptimistically(_ value: String) {
        guard let index = systemProperties.firstIndex(where: { $0.id == "dns.domain" }) else { return }
        systemProperties[index] = SystemProperty(
            id: "dns.domain",
            type: systemProperties[index].type,
            value: value,
            description: systemProperties[index].description
        )
    }

    func setSystemProperty(_ id: String, value: String) async {
        let currentApp = NSApplication.shared
        let isActive = currentApp.isActive

        // Optimistic UI update.
        if id == "dns.domain" {
            setDNSDomainPropertyOptimistically(value)
            markDNSDefault(value)
        }

        var result: ProcessResult
        do {
            result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "property", "set", id, value])
        } catch {
            result = ProcessResult(exitCode: -1, stdout: nil, stderr: error.localizedDescription)
        }

        // Restore focus if it was lost to the subprocess.
        if isActive && !currentApp.isActive {
            currentApp.activate(ignoringOtherApps: true)
        }

        if result.failed {
            alertCenter.error(result.stderr ?? "Failed to set system property")
            if id == "dns.domain" {
                await loadSystemProperties(showLoading: false)
                await reloadDNS()
            }
            return
        }

        // Success — refresh in the background to ensure consistency.
        Task {
            await self.loadSystemProperties(showLoading: false)
            if id == "dns.domain" {
                await self.reloadDNS()
            }
        }
    }
}
