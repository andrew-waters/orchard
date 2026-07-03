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
        isBuildersLoading = true

        // This runs on a 5s poll — a spawn failure (binary missing) or a nonzero exit
        // both degrade silently to .stopped and log; only user-initiated builder actions
        // (start/stop/delete) surface alerts.
        let result: ProcessResult
        do {
            result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["builder", "status", "--format", "json"]
            )
        } catch {
            builders = []
            builderStatus = .stopped
            isBuildersLoading = false
            Log.containers.error("Builder status command could not run: \(error.localizedDescription)")
            return
        }

        if result.failed {
            builders = []
            builderStatus = .stopped
            isBuildersLoading = false
            let detail = result.stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                Log.containers.error("Builder status command failed (exit \(result.exitCode)). Stderr:\n\(detail)")
            } else {
                Log.containers.error("Builder status command failed with unknown error (exit \(result.exitCode)).")
            }
            return
        }

        switch parseBuilderStatus(stdout: result.stdout ?? "") {
        case .notRunning:
            builders = []
            builderStatus = .stopped
            isBuildersLoading = false
            Log.containers.debug("Builder status indicates no builder present.")

        case .builders(let list):
            withAnimation(.easeInOut(duration: 0.3)) {
                self.builders = list
            }
            builderStatus = (list.first?.status.lowercased() == "running") ? .running : .stopped
            isBuildersLoading = false
            for b in list {
                Log.containers.debug("Builder: \(b.configuration.id), Status: \(b.status)")
            }

        case .decodeFailure(let preview):
            Log.containers.error("Failed to decode builder status. Stdout preview (first 200 chars):\n\(preview)")
            builders = []
            builderStatus = .stopped
            isBuildersLoading = false
        }
    }

    func startBuilder() async { await runBuilderCommand("start") { await self.loadBuilders() } }
    func stopBuilder() async { await runBuilderCommand("stop") { await self.loadBuilders() } }
    func deleteBuilder() async { await runBuilderCommand("delete") { self.builders = [] } }

    /// Run `container builder <verb>` (a user-initiated action), alerting on failure and
    /// running `onSuccess` when it succeeds.
    private func runBuilderCommand(_ verb: String, onSuccess: @escaping () async -> Void) async {
        isBuilderLoading = true
        alertCenter.dismiss()

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["builder", verb])
            isBuilderLoading = false
            if result.failed {
                alertCenter.error(.cliFailed(command: "builder \(verb)", exitCode: result.exitCode, stderr: result.stderr))
            } else {
                Log.containers.debug("Builder \(verb) command sent successfully")
                await onSuccess()
            }
        } catch {
            isBuilderLoading = false
            alertCenter.error("Failed to \(verb) builder: \(error.localizedDescription)")
            Log.containers.error("Error running builder \(verb): \(error.localizedDescription)")
        }
    }
}
