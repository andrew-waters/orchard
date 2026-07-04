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

    func save(_ snapshot: [StatsKey: [StatsSample]]) throws {
        let series = snapshot.map { PersistedSeries(host: $0.key.host, id: $0.key.id, samples: $0.value) }
        let data = try JSONEncoder().encode(series)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    /// Best-effort load, dropping samples older than `retention`. Returns empty on any
    /// error (missing file, corrupt JSON) — history simply starts fresh.
    func load(retention: TimeInterval = 86_400, now: Date = Date()) -> [StatsKey: [StatsSample]] {
        guard let data = try? Data(contentsOf: fileURL),
              let series = try? JSONDecoder().decode([PersistedSeries].self, from: data) else {
            return [:]
        }
        let cutoff = now.addingTimeInterval(-retention)
        var result: [StatsKey: [StatsSample]] = [:]
        for entry in series {
            let kept = entry.samples.filter { $0.timestamp >= cutoff }
            if !kept.isEmpty {
                result[StatsKey(host: entry.host, id: entry.id)] = kept
            }
        }
        return result
    }
}

/// On-disk shape: a flat list of series, since JSON object keys can't be structs.
private struct PersistedSeries: Codable {
    let host: String
    let id: String
    let samples: [StatsSample]
}
