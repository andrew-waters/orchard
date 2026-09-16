import Foundation

/// Whether the `container compose` CLI plugin is on this machine, and fetching it when it
/// is not.
///
/// Orchard does not need it. The window links ComposePlanner and runs plans over XPC, so
/// every compose project works with nothing installed. The plugin is what makes
/// `container compose up` work in a terminal, and it is worth offering because container's
/// own installer clears the plugin directory on every upgrade (apple/container#1617), so a
/// plugin someone installed by hand goes missing again through no fault of theirs.
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

        /// What the step is waiting on, when that is not obvious from the title. The last one
        /// is waiting on a person, which is worth saying rather than looking stalled.
        var note: String? {
            switch self {
            case .installing: return "Authorisation required"
            default: return nil
            }
        }
    }

    @Published private(set) var state: State = .unknown

    /// The release being installed, once it is known, so the sheet can name a version while
    /// it works rather than after.
    @Published private(set) var targetVersion: String?

    private var installTask: Task<Void, Never>?

    /// The directories `container` searches, in the order its own error message lists them.
    /// The first is what the plugin's Makefile installs into; the second is where container
    /// keeps the plugins it ships itself.
    static let searchPaths = [
        "/usr/local/libexec/container-plugins/compose",
        "/usr/local/libexec/container/plugins/compose",
    ]

    /// Where the install goes: the first search path, because writing into container's own
    /// plugin directory would put this among files its installer owns.
    static let installPath = searchPaths[0]

    /// The release this fetches from. Apple silicon only, which is all the runtime runs on.
    static let releaseAPI = URL(string: "https://api.github.com/repos/andrew-waters/compose/releases/latest")!
    static let assetSuffix = "-macos-arm64.tar.gz"

    private let commandRunner: any CommandRunner
    private let fileManager: FileManager
    private let session: URLSession

    init(
        commandRunner: any CommandRunner = SystemCommandRunner(),
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.session = session
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
    /// Called when the Compose tab is opened rather than polled: it only changes when someone
    /// installs it or container's installer clears the directory, and both happen between
    /// visits to this tab.
    func refresh() async {
        guard let binary = Self.installedBinaryPath(fileManager: fileManager) else {
            state = .missing
            return
        }
        state = .installed(version: await Self.version(of: binary, using: commandRunner))
    }

    /// The installed plugin binary, from whichever directory the CLI would find a *complete*
    /// plugin in.
    ///
    /// Both files are required. The CLI needs `config.toml` next to `bin/compose` and reports
    /// only "Plugin not found" when either is absent, so a directory holding half a plugin has
    /// to count as missing here. Otherwise the banner goes away while the command still fails,
    /// which is the least useful thing this could do.
    static func installedBinaryPath(fileManager: FileManager = .default) -> String? {
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

    /// Copy the two files into the plugin directory behind one admin prompt.
    ///
    /// Returns false when the prompt was dismissed. `install` is used rather than `cp` because
    /// it makes the directories and sets the modes in one go, and the layout has to be exact:
    /// a plugin is a directory named after its binary, holding `config.toml` and `bin/<name>`.
    /// Miss either and the CLI reports only "Plugin not found", with nothing to say which half
    /// is wrong. Writing the two files in place also means nothing is removed as root.
    private func copyIntoPlace(from unpacked: URL) async throws -> Bool {
        let dir = Self.installPath
        let binary = unpacked.appendingPathComponent("bin/compose").path
        let config = unpacked.appendingPathComponent("config.toml").path
        let script = """
            /usr/bin/install -d \(SystemCommandRunner.shellQuote(dir + "/bin")) && \
            /usr/bin/install -m 0755 \(SystemCommandRunner.shellQuote(binary)) \
            \(SystemCommandRunner.shellQuote(dir + "/bin/compose")) && \
            /usr/bin/install -m 0644 \(SystemCommandRunner.shellQuote(config)) \
            \(SystemCommandRunner.shellQuote(dir + "/config.toml"))
            """

        let result = try await commandRunner.runWithSudo(program: "/bin/sh", arguments: ["-c", script])
        guard result.failed else { return true }

        let message = result.stderr ?? ""
        if message.contains("User canceled") || message.contains("-128") { return false }
        throw InstallError.badResponse
    }
}
