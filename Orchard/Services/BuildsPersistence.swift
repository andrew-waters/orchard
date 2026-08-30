import Foundation

/// Reads and writes the image-build registry to disk so build records (and
/// their logs) survive an app relaunch. One JSON file holding every record.
struct BuildsPersistence: Sendable {
    let fileURL: URL

    init(fileURL: URL = BuildsPersistence.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orchard", isDirectory: true)
            .appendingPathComponent("builds.json")
    }

    /// Current on-disk schema version. Bump when `ImageBuild` changes shape;
    /// `load` drops anything stamped with a different version rather than
    /// letting a decode mismatch silently corrupt the registry.
    static let currentVersion = 1

    /// Transcript lines kept per build on disk. The live registry holds more,
    /// but the persisted tail keeps the file lean.
    static let persistedTranscriptLines = 1000

    func save(_ builds: [ImageBuild]) throws {
        let trimmed = builds.map { build in
            var build = build
            if build.outputLines.count > Self.persistedTranscriptLines {
                build.outputLines.removeFirst(build.outputLines.count - Self.persistedTranscriptLines)
            }
            return build
        }
        let file = PersistedFile(version: Self.currentVersion, builds: trimmed)
        let data = try JSONEncoder().encode(file)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    /// Best-effort load. Returns empty on any error (missing file, corrupt
    /// JSON, or a schema version this build doesn't understand) — the registry
    /// simply starts fresh rather than crashing or mis-decoding.
    func load() -> [ImageBuild] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(PersistedFile.self, from: data),
              file.version == Self.currentVersion else {
            return []
        }
        return file.builds
    }
}

/// On-disk shape: a versioned envelope so a future format change can migrate
/// or drop cleanly.
private struct PersistedFile: Codable {
    let version: Int
    let builds: [ImageBuild]
}
