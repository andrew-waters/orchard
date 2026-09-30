import Foundation

/// Whether the `container compose` CLI plugin is on this machine, and fetching it when it
/// is not.
///
/// Orchard does not need it. The window links ComposePlanner and runs plans over XPC, so
/// every compose project works with nothing installed. The plugin is what makes
/// `container compose up` work in a terminal, and it is worth offering because an upgrade
/// can take it away: container looks for plugins under its versioned install root, so a
/// Homebrew upgrade moves to a new keg and every plugin installed by hand is left behind in
/// the old one (apple/container#1617, #113).
///
/// That is also why this only ever informs. Nothing here blocks, and a missing plugin is
/// never an error state for the app.
///
/// The install is the one the project documents by hand: fetch the release tarball, unpack
/// it, and put the two files it holds where the CLI looks. Fetching rather than bundling
/// means the newest published plugin is installed whatever Orchard's own age, and that
/// Orchard ships no copy of a binary it never runs.
@MainActor
final class ComposePluginService: ObservableObject {
    enum State: Equatable {
        /// Not looked yet.
        case unknown
        /// Present, with the version it reports when it could be read.
        case installed(version: String?)
        /// Absent, or present in a form the CLI will not load.
        case missing
        /// Under way, at a named step. Steps rather than free text because the sheet shows
        /// the whole sequence and ticks them off: on a slow connection a bare spinner would
        /// look stuck, and a lone caption gives no sense of how much is left.
        case working(Step)
        /// Attempted and did not finish. Carries what to tell the user, which is never a raw
        /// networking or osascript error.
        case failed(String)
    }

    /// The stages of an install, in the order they happen. The sheet lists all of them and
    /// marks each one done as it passes, so the length of the job is visible from the start.
    enum Step: Int, CaseIterable, Equatable {
        case findingRelease
        case downloading
        case unpacking
        case installing

        var title: String {
            switch self {
            case .findingRelease: return "Finding the latest release"
            case .downloading: return "Downloading"
            case .unpacking: return "Unpacking"
            case .installing: return "Installing"
            }
        }

    }

    /// What a step is waiting on, when that is not obvious from its title. Installing waits on
    /// a person when the plugin directory needs an administrator, which is worth saying rather
    /// than looking stalled.
    func note(for step: Step) -> String? {
        step == .installing && Self.needsAdministrator(toWrite: installPath, fileManager: fileManager)
            ? "Authorisation required" : nil
    }

    @Published private(set) var state: State = .unknown

    /// The release being installed, once it is known, so the sheet can name a version while
    /// it works rather than after.
    @Published private(set) var targetVersion: String?

    private var installTask: Task<Void, Never>?

    /// Where a pkg-installed `container` looks, in the order its own error message lists
    /// them. Only a fallback: the directories depend on where the CLI is installed, so the CLI
    /// is asked first (see `refresh`), and these stand in when it cannot answer.
    static let defaultSearchPaths = [
        "/usr/local/libexec/container-plugins/compose",
        "/usr/local/libexec/container/plugins/compose",
    ]

    /// The directories the configured CLI searches, as it last reported them. The first is
    /// where an install goes: the second is container's own plugin directory, among files its
    /// installer owns. For Homebrew the first is inside the current keg, which is the only
    /// place that version will look.
    @Published private(set) var searchPaths = defaultSearchPaths

    var installPath: String { searchPaths.first ?? Self.defaultSearchPaths[0] }

    /// The release this fetches from. Apple silicon only, which is all the runtime runs on.
    static let releaseAPI = URL(string: "https://api.github.com/repos/andrew-waters/compose/releases/latest")!
    static let assetSuffix = "-macos-arm64.tar.gz"

    private let commandRunner: any CommandRunner
    private let fileManager: FileManager
    private let session: URLSession
    private let containerBinaryPath: @MainActor () -> String

    init(
        commandRunner: any CommandRunner = SystemCommandRunner(),
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        containerBinaryPath: @escaping @MainActor () -> String = { "/usr/local/bin/container" }
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.session = session
        self.containerBinaryPath = containerBinaryPath
    }

    var isMissing: Bool { state == .missing }

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    /// The step running now, or nil when nothing is.
    var currentStep: Step? {
        if case .working(let step) = state { return step }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// The version now on the machine, once an install has finished.
    var installedVersion: String? {
        if case .installed(let version) = state { return version }
        return nil
    }

    /// Look for the plugin, and read its version if it answers.
    ///
    /// Asks the CLI, through `container compose --version`, rather than looking at fixed
    /// paths: what matters is whether the command works in a terminal, and where the CLI looks
    /// depends on how it was installed. Checking `/usr/local` alone said "installed" to a
    /// Homebrew user whose CLI could not see that copy, so the reinstall was never offered
    /// (#113). When the plugin is missing, the CLI's error names the directories it searched,
    /// which is where an install has to go.
    ///
    /// Called when the Compose tab is opened rather than polled: it only changes when someone
    /// installs it or an upgrade leaves it behind, and both happen between visits to this tab.
    func refresh() async {
        let result = try? await commandRunner.run(program: containerBinaryPath(), arguments: ["compose", "--version"])
        if let result, !result.failed {
            let version = result.stdout?.trimmingCharacters(in: .whitespacesAndNewlines)
            state = .installed(version: version?.isEmpty == false ? version : nil)
            return
        }

        let output = [result?.stderr, result?.stdout].compactMap { $0 }.joined(separator: "\n")
        if Self.indicatesMissingPlugin(output) {
            let searched = Self.searchedDirectories(inCLIError: output)
            if !searched.isEmpty { searchPaths = searched }
            state = .missing
            return
        }

        // The CLI could not say, typically because the system is stopped ("Plugins are
        // unavailable"). Fall back to looking where it last said it searches.
        guard let binary = installedBinaryPath() else {
            state = .missing
            return
        }
        state = .installed(version: await Self.version(of: binary, using: commandRunner))
    }

    /// True when the CLI's output says it has no `compose` command: "unknown command" from
    /// 1.5.0, "Plugin 'container-compose' not found" before.
    nonisolated static func indicatesMissingPlugin(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("unknown command 'compose'")
            || (lower.contains("plugin 'container-compose'") && lower.contains("not found"))
    }

    /// The plugin directories listed in the CLI's missing-plugin error, e.g. the
    /// `  - /opt/homebrew/Cellar/container/1.5.0/libexec/container-plugins/compose` lines.
    nonisolated static func searchedDirectories(inCLIError output: String) -> [String] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- /") else { return nil }
            let path = String(trimmed.dropFirst(2))
            return path.hasSuffix("/compose") ? path : nil
        }
    }

    /// True when writing `path` needs an administrator: the nearest directory that already
    /// exists is not writable by this user. A Homebrew prefix is the user's own, so a plugin
    /// goes in there without a prompt, and without leaving root-owned files in the keg.
    nonisolated static func needsAdministrator(toWrite path: String, fileManager: FileManager = .default) -> Bool {
        var candidate = URL(fileURLWithPath: path)
        while !fileManager.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return !fileManager.isWritableFile(atPath: candidate.path)
    }

    /// The installed plugin binary, from whichever directory the CLI would find a *complete*
    /// plugin in.
    ///
    /// Both files are required. The CLI needs `config.toml` next to `bin/compose` and reports
    /// only "Plugin not found" when either is absent, so a directory holding half a plugin has
    /// to count as missing here. Otherwise the banner goes away while the command still fails,
    /// which is the least useful thing this could do.
    func installedBinaryPath() -> String? {
        searchPaths
            .first {
                fileManager.isExecutableFile(atPath: $0 + "/bin/compose")
                    && fileManager.isReadableFile(atPath: $0 + "/config.toml")
            }
            .map { $0 + "/bin/compose" }
    }

    /// Ask the plugin what version it is. A binary that will not answer is still installed, so
    /// this reports nil rather than treating it as absent.
    private static func version(of binary: String, using runner: any CommandRunner) async -> String? {
        guard let result = try? await runner.run(program: binary, arguments: ["--version"]) else { return nil }
        guard !result.failed else { return nil }
        return result.stdout?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Install

    private struct Release {
        let tag: String
        let assetURL: URL
    }

    private enum InstallError: Error {
        /// The release exists but publishes nothing for this architecture.
        case noAsset
        case badResponse
    }

    /// Start an install, unless one is already running.
    ///
    /// The task is held so the sheet can cancel it: this downloads 15MB, and someone who
    /// started it by accident should not have to wait it out.
    func beginInstall() {
        guard installTask == nil else { return }
        installTask = Task { [weak self] in
            await self?.install()
            self?.installTask = nil
        }
    }

    /// Stop an install in flight and go back to describing the machine as it is.
    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        targetVersion = nil
        Task { await refresh() }
    }

    /// Fetch the newest release and put it where the CLI looks.
    ///
    /// Everything up to the final copy happens unprivileged in a temporary directory, so the
    /// password is asked for once, at the end, for the two files that actually land in a
    /// root-owned directory. A failure before that point never prompts at all.
    func install() async {
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("orchard-compose-plugin-\(UUID().uuidString)")

        do {
            state = .working(.findingRelease)
            let release = try await latestRelease()
            targetVersion = release.tag
            try Task.checkCancellation()

            state = .working(.downloading)
            try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
            let tarball = scratch.appendingPathComponent("compose.tar.gz")
            try await download(release.assetURL, to: tarball)

            try Task.checkCancellation()
            state = .working(.unpacking)
            let unpacked = try await unpack(tarball, in: scratch)

            try Task.checkCancellation()
            state = .working(.installing)
            guard try await copyIntoPlace(from: unpacked) else {
                // The authorisation prompt was dismissed. Not a failure worth reporting: go
                // back to describing whatever the machine actually looks like.
                try? fileManager.removeItem(at: scratch)
                await refresh()
                return
            }
        } catch is CancellationError {
            try? fileManager.removeItem(at: scratch)
            return
        } catch InstallError.noAsset {
            try? fileManager.removeItem(at: scratch)
            state = .failed("That release has no build for Apple silicon.")
            return
        } catch let error as URLError where error.code == .notConnectedToInternet {
            try? fileManager.removeItem(at: scratch)
            state = .failed("No network connection.")
            return
        } catch {
            try? fileManager.removeItem(at: scratch)
            state = .failed("The plugin could not be installed.")
            return
        }

        try? fileManager.removeItem(at: scratch)
        await refresh()
    }

    /// The newest published release, and the asset built for this machine.
    private func latestRelease() async throws -> Release {
        var request = URLRequest(url: Self.releaseAPI)
        // GitHub refuses API requests that do not identify themselves.
        request.setValue("Orchard", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.badResponse
        }

        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadURL: URL

                enum CodingKeys: String, CodingKey {
                    case name
                    case browserDownloadURL = "browser_download_url"
                }
            }

            let tagName: String
            let assets: [Asset]

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case assets
            }
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let asset = payload.assets.first(where: { $0.name.hasSuffix(Self.assetSuffix) }) else {
            throw InstallError.noAsset
        }
        return Release(tag: payload.tagName, assetURL: asset.browserDownloadURL)
    }

    private func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("Orchard", forHTTPHeaderField: "User-Agent")

        let (temporary, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.badResponse
        }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    /// Unpack the tarball and return the plugin directory inside it.
    ///
    /// The archive is the plugin directory exactly as it installs, so unpacking gives a
    /// `compose/` holding `config.toml` and `bin/compose` and nothing has to be assembled.
    /// Both are checked for before anything asks for a password, so a truncated or unexpected
    /// archive fails quietly rather than after an authorisation prompt.
    private func unpack(_ tarball: URL, in directory: URL) async throws -> URL {
        let result = try await commandRunner.run(
            program: "/usr/bin/tar",
            arguments: ["-xzf", tarball.path, "-C", directory.path]
        )
        guard !result.failed else { throw InstallError.badResponse }

        let unpacked = directory.appendingPathComponent("compose")
        guard fileManager.isReadableFile(atPath: unpacked.appendingPathComponent("config.toml").path),
              fileManager.isExecutableFile(atPath: unpacked.appendingPathComponent("bin/compose").path)
        else {
            throw InstallError.badResponse
        }
        return unpacked
    }

    /// Copy the two files into the plugin directory, behind one admin prompt when the
    /// directory needs it.
    ///
    /// Returns false when the prompt was dismissed. `install` is used rather than `cp` because
    /// it makes the directories and sets the modes in one go, and the layout has to be exact:
    /// a plugin is a directory named after its binary, holding `config.toml` and `bin/<name>`.
    /// Miss either and the CLI reports only "Plugin not found", with nothing to say which half
    /// is wrong. Writing the two files in place also means nothing is removed as root.
    private func copyIntoPlace(from unpacked: URL) async throws -> Bool {
        let dir = installPath
        let binary = unpacked.appendingPathComponent("bin/compose").path
        let config = unpacked.appendingPathComponent("config.toml").path
        let script = """
            /usr/bin/install -d \(SystemCommandRunner.shellQuote(dir + "/bin")) && \
            /usr/bin/install -m 0755 \(SystemCommandRunner.shellQuote(binary)) \
            \(SystemCommandRunner.shellQuote(dir + "/bin/compose")) && \
            /usr/bin/install -m 0644 \(SystemCommandRunner.shellQuote(config)) \
            \(SystemCommandRunner.shellQuote(dir + "/config.toml"))
            """

        let result = Self.needsAdministrator(toWrite: dir, fileManager: fileManager)
            ? try await commandRunner.runWithSudo(program: "/bin/sh", arguments: ["-c", script])
            : try await commandRunner.run(program: "/bin/sh", arguments: ["-c", script])
        guard result.failed else { return true }

        let message = result.stderr ?? ""
        if message.contains("User canceled") || message.contains("-128") { return false }
        throw InstallError.badResponse
    }
}
