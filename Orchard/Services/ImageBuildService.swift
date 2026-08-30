import Foundation
import SwiftUI

/// Drives `container build` for the Build Image sheet. The CLI owns the hard
/// parts (starting or restarting the BuildKit builder, dialing it, unpacking
/// the result), so Orchard shells out and streams the build log; `--progress
/// plain` keeps the output line-oriented for the console view.
@MainActor
final class ImageBuildService: ObservableObject {

    struct Request: Equatable {
        var dockerfile: String
        var contextDir: String
        var tag: String
        /// "arm64" or "amd64" — the CLI's `--arch` values.
        var arch: String
        var noCache: Bool
    }

    enum Phase: Equatable {
        case idle
        case building
        case succeeded(tag: String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var outputLines: [String] = []

    var isBuilding: Bool { phase == .building }

    /// Refresh the image list after a successful build. Set by the owner.
    var onImageBuilt: () async -> Void = {}

    private let runner: CommandRunner
    private let settings: SettingsStore
    private var buildTask: Task<Void, Never>?

    init(runner: CommandRunner, settings: SettingsStore) {
        self.runner = runner
        self.settings = settings
    }

    // MARK: - Pure request handling (unit-tested)

    /// The `container` CLI arguments for a build request. The context directory
    /// comes last (positional); `--progress plain` keeps output parseable.
    nonisolated static func arguments(for request: Request) -> [String] {
        var arguments = [
            "build",
            "--file", request.dockerfile,
            "--tag", request.tag,
            "--arch", request.arch,
            "--progress", "plain",
        ]
        if request.noCache {
            arguments.append("--no-cache")
        }
        arguments.append(request.contextDir)
        return arguments
    }

    /// nil when the request is buildable, else a user-facing message. Field
    /// values are expected pre-trimmed (the sheet trims before calling).
    nonisolated static func validationError(for request: Request, fileManager: FileManager = .default) -> String? {
        if request.dockerfile.isEmpty {
            return "Choose a Dockerfile to build."
        }
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: request.dockerfile, isDirectory: &isDirectory) || isDirectory.boolValue {
            return "No file exists at the Dockerfile path."
        }
        if request.contextDir.isEmpty {
            return "Choose a build context directory."
        }
        if !fileManager.fileExists(atPath: request.contextDir, isDirectory: &isDirectory) || !isDirectory.boolValue {
            return "The build context is not a directory."
        }
        if request.tag.isEmpty {
            return "Name the image (e.g. myapp:latest)."
        }
        // The repository half must be lowercase; a tag half may be mixed case.
        let pattern = "^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9._-]+)?$"
        if request.tag.range(of: pattern, options: .regularExpression) == nil {
            return "Invalid image name. Use lowercase letters, digits, separators, and an optional :tag."
        }
        return nil
    }

    // MARK: - Lifecycle

    func build(_ request: Request) {
        guard !isBuilding else { return }

        phase = .building
        outputLines = []

        let program = settings.safeContainerBinaryPath()
        let arguments = Self.arguments(for: request)
        let runner = runner

        buildTask = Task { [weak self] in
            do {
                let result = try await runner.runStreaming(program: program, arguments: arguments) { line in
                    Task { @MainActor [weak self] in
                        self?.append(line)
                    }
                }
                guard let self, !Task.isCancelled else { return }
                if result.failed {
                    self.phase = .failed(Self.failureSummary(from: result))
                } else {
                    self.phase = .succeeded(tag: request.tag)
                    await self.onImageBuilt()
                }
            } catch {
                guard let self else { return }
                if Task.isCancelled {
                    self.append("Build cancelled.")
                    self.phase = .idle
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        guard isBuilding else { return }
        buildTask?.cancel()
        buildTask = nil
        append("Build cancelled.")
        phase = .idle
    }

    /// Clear finished state when the sheet is reopened; a running build is
    /// deliberately left alone so closing the sheet doesn't kill it.
    func resetIfFinished() {
        guard !isBuilding else { return }
        phase = .idle
        outputLines = []
    }

    private func append(_ line: String) {
        outputLines.append(line)
        // Keep a long but bounded transcript: BuildKit can be chatty and the
        // console re-renders on every change.
        if outputLines.count > 4000 {
            outputLines.removeFirst(outputLines.count - 4000)
        }
    }

    /// The most useful line to headline a failure: the last non-empty stderr
    /// line if any, else the exit code.
    nonisolated static func failureSummary(from result: ProcessResult) -> String {
        let lastError = (result.stderr ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return lastError ?? "Build failed with exit code \(result.exitCode)."
    }
}
