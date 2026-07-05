import Foundation

/// Reads and writes container stats history to disk so the 1h/24h windows survive an app
/// relaunch. One JSON file holding every series; pruned to the retention window on load.
struct StatsPersistence: Sendable {
    let fileURL: URL

    init(fileURL: URL = StatsPersistence.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orchard", isDirectory: true)
            .appendingPathComponent("stats-history.json")
    }

    /// Current on-disk schema version. Bump when `StatsSample`/`PersistedSeries` change shape;
    /// `load` drops (or, in future, migrates) anything stamped with a different version rather
    /// than letting a decode mismatch silently wipe history.
    static let currentVersion = 1

    func save(_ snapshot: [StatsKey: [StatsSample]]) throws {
        let series = snapshot.map { PersistedSeries(host: $0.key.host, id: $0.key.id, samples: $0.value) }
        let file = PersistedFile(version: Self.currentVersion, series: series)
        let data = try JSONEncoder().encode(file)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    /// Best-effort load, dropping samples older than `retention`. Returns empty on any
    /// error (missing file, corrupt JSON, or a schema version this build doesn't understand) —
    /// history simply starts fresh rather than crashing or mis-decoding.
    func load(retention: TimeInterval = 86_400, now: Date = Date()) -> [StatsKey: [StatsSample]] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(PersistedFile.self, from: data),
              file.version == Self.currentVersion else {
            return [:]
        }
        let cutoff = now.addingTimeInterval(-retention)
        var result: [StatsKey: [StatsSample]] = [:]
        for entry in file.series {
            let kept = entry.samples.filter { $0.timestamp >= cutoff }
            if !kept.isEmpty {
                result[StatsKey(host: entry.host, id: entry.id)] = kept
            }
        }
        return result
    }
}

/// On-disk shape: a versioned envelope around a flat list of series (JSON object keys can't
/// be structs). The `version` lets a future format change migrate or drop cleanly.
private struct PersistedFile: Codable {
    let version: Int
    let series: [PersistedSeries]
}

private struct PersistedSeries: Codable {
    let host: String
    let id: String
    let samples: [StatsSample]
}
