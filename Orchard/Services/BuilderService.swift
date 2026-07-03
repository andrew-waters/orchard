import Foundation
import SwiftUI

enum BuilderStatus {
    case stopped
    case running

    var color: Color {
        switch self {
        case .stopped: return .gray
        case .running: return .green
        }
    }

    var text: String {
        switch self {
        case .stopped: return "Stopped"
        case .running: return "Running"
        }
    }
}

/// Owns BuildKit builder state and lifecycle, backed by the `container builder` CLI.
@MainActor
final class BuilderService: ObservableObject {
    @Published var builders: [Builder] = []
    @Published var builderStatus: BuilderStatus = .stopped
    @Published var isBuilderLoading = false
    @Published var isBuildersLoading = false

    private let runner: CommandRunner
    private let settings: SettingsStore
    private let alertCenter: AlertCenter

    init(runner: CommandRunner, settings: SettingsStore, alertCenter: AlertCenter) {
        self.runner = runner
        self.settings = settings
        self.alertCenter = alertCenter
    }

    func loadBuilders() async {
        await MainActor.run {
            isBuildersLoading = true
        }

        var result: ProcessResult
        do {
            result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["builder", "status", "--format", "json"]
            )
        } catch {
            result = ProcessResult(exitCode: -1, stdout: nil, stderr: error.localizedDescription)
        }

        if result.failed {
            let detail = result.stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
            // This runs on a 5s poll — degrade silently to .stopped and log; only the
            // user-initiated builder actions (start/stop/delete) surface alerts.
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            if let detail, !detail.isEmpty {
                Log.containers.error("Builder status command failed (exit \(result.exitCode)). Stderr:\n\(detail)")
            } else {
                Log.containers.error("Builder status command failed with unknown error (exit \(result.exitCode)).")
            }
            return
        }

        switch parseBuilderStatus(stdout: result.stdout ?? "") {
        case .notRunning:
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
            Log.containers.debug("Builder status indicates no builder present.")

        case .builders(let list):
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.builders = list
                }
                self.builderStatus = (list.first?.status.lowercased() == "running") ? .running : .stopped
                self.isBuildersLoading = false
            }
            for b in list {
                Log.containers.debug("Builder: \(b.configuration.id), Status: \(b.status)")
            }

        case .decodeFailure(let preview):
            Log.containers.error("Failed to decode builder status. Stdout preview (first 200 chars):\n\(preview)")
            await MainActor.run {
                self.builders = []
                self.builderStatus = .stopped
                self.isBuildersLoading = false
            }
        }
    }

    func startBuilder() async {
        await MainActor.run {
            isBuilderLoading = true
            self.alertCenter.dismiss()
        }

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["builder", "start"])

            await MainActor.run {
                if !result.failed {
                    Log.containers.debug("Builder start command sent successfully")
                    self.isBuilderLoading = false
                    Task { await self.loadBuilders() }
                } else {
                    self.alertCenter.error("Failed to start builder: \(result.stderr ?? "Unknown error")")
                    self.isBuilderLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.isBuilderLoading = false
                self.alertCenter.error("Failed to start builder: \(error.localizedDescription)")
            }
            Log.containers.error("Error starting builder: \(error.localizedDescription)")
        }
    }

    func stopBuilder() async {
        await MainActor.run {
            isBuilderLoading = true
            self.alertCenter.dismiss()
        }

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["builder", "stop"])

            await MainActor.run {
                if !result.failed {
                    Log.containers.debug("Builder stop command sent successfully")
                    self.isBuilderLoading = false
                    Task { await self.loadBuilders() }
                } else {
                    self.alertCenter.error("Failed to stop builder: \(result.stderr ?? "Unknown error")")
                    self.isBuilderLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.isBuilderLoading = false
                self.alertCenter.error("Failed to stop builder: \(error.localizedDescription)")
            }
            Log.containers.error("Error stopping builder: \(error.localizedDescription)")
        }
    }

    func deleteBuilder() async {
        await MainActor.run {
            isBuilderLoading = true
            self.alertCenter.dismiss()
        }

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["builder", "delete"])

            await MainActor.run {
                if !result.failed {
                    Log.containers.debug("Builder delete command sent successfully")
                    self.isBuilderLoading = false
                    self.builders = []
                } else {
                    self.alertCenter.error("Failed to delete builder: \(result.stderr ?? "Unknown error")")
                    self.isBuilderLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.isBuilderLoading = false
                self.alertCenter.error("Failed to delete builder: \(error.localizedDescription)")
            }
            Log.containers.error("Error deleting builder: \(error.localizedDescription)")
        }
    }
}
