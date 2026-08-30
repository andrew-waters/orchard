import Foundation
import SwiftUI

/// One tracked `container build` run. The registry persists across launches,
/// but only holds builds Orchard itself started: the builder shim's gRPC
/// surface is just info() + a build stream, so there is no host-reachable
/// BuildKit history to enumerate.
struct ImageBuild: Identifiable, Equatable, Codable {
    enum Phase: Equatable, Codable {
        case building
        case succeeded
        case failed(String)
        case cancelled
        /// The app quit while this build was running. The spawned CLI was
        /// orphaned, so the outcome was never observed - the image may still
        /// have been produced.
        case interrupted

        var isFinished: Bool { self != .building }
    }

    let id: UUID
    let request: ImageBuildService.Request
    let startedAt: Date
    var phase: Phase = .building
    var outputLines: [String] = []
    var finishedAt: Date?

    var tag: String { request.tag }

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

/// Drives `container build` and keeps a registry of the builds this app
/// session started. The CLI owns the hard parts (starting or restarting the
/// BuildKit builder, dialing it, unpacking the result), so Orchard shells out
/// and streams each build log; `--progress plain` keeps output line-oriented
/// for the console view. Builds may run concurrently - BuildKit queues and
/// interleaves them itself.
@MainActor
final class ImageBuildService: ObservableObject {

    struct Request: Equatable, Codable {
        var dockerfile: String
        var contextDir: String
        var tag: String
        /// "arm64" or "amd64" — the CLI's `--arch` values.
        var arch: String
        var noCache: Bool
    }

    /// Newest first. Finished builds are kept (capped) so their logs stay
    /// reviewable from the Builds menu until cleared, and the registry is
    /// persisted so records survive a relaunch.
    @Published private(set) var builds: [ImageBuild] = []

    var runningCount: Int { builds.lazy.filter { $0.phase == .building }.count }

    /// Refresh the image list after a successful build. Set by the owner.
    var onImageBuilt: () async -> Void = {}

    private let runner: CommandRunner
    private let settings: SettingsStore
    private let persistence: BuildsPersistence
    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Finished builds kept in the registry before the oldest are dropped.
    private static let maxFinishedBuilds = 20
    /// Transcript cap per build: BuildKit can be chatty and the console
    /// re-renders on every change.
    private static let maxTranscriptLines = 4000

    init(runner: CommandRunner, settings: SettingsStore, persistence: BuildsPersistence = BuildsPersistence()) {
        self.runner = runner
        self.settings = settings
        self.persistence = persistence
        // Restore prior records. Anything still marked building belonged to a
        // previous process: its CLI child was orphaned at quit and the outcome
        // never observed, so mark it interrupted rather than leave it lying.
        builds = persistence.load().map { build in
            guard build.phase == .building else { return build }
            var build = build
            build.phase = .interrupted
            build.finishedAt = build.finishedAt ?? Date()
            build.outputLines.append("Orchard quit while this build was running; the result was not tracked (the image may still have been built).")
            return build
        }
    }

    func build(id: UUID) -> ImageBuild? {
        builds.first { $0.id == id }
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

    /// The most useful line to headline a failure: the last non-empty stderr
    /// line if any, else the exit code.
    nonisolated static func failureSummary(from result: ProcessResult) -> String {
        let lastError = (result.stderr ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return lastError ?? "Build failed with exit code \(result.exitCode)."
    }

    // MARK: - Lifecycle

    /// Start a build and return its registry id.
    @discardableResult
    func startBuild(_ request: Request) -> UUID {
        let buildID = UUID()
        builds.insert(ImageBuild(id: buildID, request: request, startedAt: Date()), at: 0)
        pruneFinished()

        let program = settings.safeContainerBinaryPath()
        let arguments = Self.arguments(for: request)
        let runner = runner

        persist()

        tasks[buildID] = Task { [weak self] in
            do {
                let result = try await runner.runStreaming(program: program, arguments: arguments) { line in
                    Task { @MainActor [weak self] in
                        self?.append(line, to: buildID)
                    }
                }
                guard let self else { return }
                // A cancel() already finalized the record; don't overwrite it.
                guard self.build(id: buildID)?.phase == .building else { return }
                if result.failed {
                    self.finish(buildID, as: .failed(Self.failureSummary(from: result)))
                } else {
                    self.finish(buildID, as: .succeeded)
                    await self.onImageBuilt()
                }
            } catch {
                guard let self, self.build(id: buildID)?.phase == .building else { return }
                self.finish(buildID, as: .failed(error.localizedDescription))
            }
        }
        return buildID
    }

    func cancel(_ id: UUID) {
        guard build(id: id)?.phase == .building else { return }
        tasks[id]?.cancel()
        append("Build cancelled.", to: id)
        finish(id, as: .cancelled)
    }

    /// Drop finished builds from the registry (running ones stay).
    func clearFinished() {
        builds.removeAll { $0.phase.isFinished }
        persist()
    }

    // MARK: - Registry mutation

    private func mutate(_ id: UUID, _ change: (inout ImageBuild) -> Void) {
        guard let index = builds.firstIndex(where: { $0.id == id }) else { return }
        change(&builds[index])
    }

    private func append(_ line: String, to id: UUID) {
        mutate(id) { build in
            build.outputLines.append(line)
            if build.outputLines.count > Self.maxTranscriptLines {
                build.outputLines.removeFirst(build.outputLines.count - Self.maxTranscriptLines)
            }
        }
    }

    private func finish(_ id: UUID, as phase: ImageBuild.Phase) {
        tasks.removeValue(forKey: id)
        mutate(id) { build in
            build.phase = phase
            build.finishedAt = Date()
        }
        persist()
    }

    /// Write the registry to disk. Called on lifecycle edges (start, finish,
    /// cancel, clear) - never per output line, so a running build's transcript
    /// only hits disk when it finishes.
    private func persist() {
        do {
            try persistence.save(builds)
        } catch {
            Log.containers.error("Failed to persist build records: \(error.localizedDescription)")
        }
    }

    private func pruneFinished() {
        let finished = builds.filter { $0.phase.isFinished }
        guard finished.count > Self.maxFinishedBuilds else { return }
        let dropIDs = Set(finished.suffix(finished.count - Self.maxFinishedBuilds).map(\.id))
        builds.removeAll { dropIDs.contains($0.id) }
    }
}
