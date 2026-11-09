import Foundation

/// Whether container's rebuildable data is left out of Time Machine.
///
/// Container 1.7.1 excludes `snapshots/` and `containers/` under its app root from backups
/// (apple/container#2412), but only when it first creates them. An install from before keeps
/// backing up their large sparse files, which slows backups and can thin older ones. Both can
/// be rebuilt, by pulling the image or recreating the container. `volumes/` holds named volume
/// data and stays backed up on purpose: nothing here ever touches it.
///
/// The exclusion is the sticky one upstream sets, `isExcludedFromBackup`, which is what
/// `tmutil addexclusion` sets too. It is only ever set when the user asks.
struct BackupExclusion {
    /// The directories that are safe to leave out, under the app root.
    static let rebuildableDirectories = ["snapshots", "containers"]

    enum State: Equatable {
        /// Every rebuildable directory that exists is left out of backups.
        case excluded
        /// These directories are still backed up.
        case included([String])
        /// None of them exist yet: nothing to back up or exclude.
        case missing
    }

    /// container's default app root.
    static var defaultAppRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.apple.container", isDirectory: true)
    }

    let appRoot: URL

    init(appRoot: URL = BackupExclusion.defaultAppRoot) {
        self.appRoot = appRoot
    }

    private func url(_ name: String) -> URL {
        appRoot.appendingPathComponent(name, isDirectory: true)
    }

    private var existingDirectories: [String] {
        Self.rebuildableDirectories.filter { FileManager.default.fileExists(atPath: url($0).path) }
    }

    func state() -> State {
        let existing = existingDirectories
        guard !existing.isEmpty else { return .missing }
        let included = existing.filter { name in
            let values = try? url(name).resourceValues(forKeys: [.isExcludedFromBackupKey])
            return values?.isExcludedFromBackup != true
        }
        return included.isEmpty ? .excluded : .included(included)
    }

    /// Leave every existing rebuildable directory out of backups. Never creates one, and never
    /// touches `volumes/`.
    func excludeRebuildable() throws {
        for name in existingDirectories {
            var directory = url(name)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
    }
}
