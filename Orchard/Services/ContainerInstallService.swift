import Foundation

/// Installing Apple container when it is not on the machine (#145).
///
/// Orchard is nothing without container, so when the binary is missing the window says so
/// and offers to put it there. The install is the one upstream documents: Apple's signed
/// pkg, run through `installer`. It is the release this build of Orchard links
/// (`supportedContainerVersion`) rather than the newest, so what gets installed is a version
/// the app can talk to.
///
/// The pkg is downloaded and its signature checked unprivileged, in a temporary directory,
/// so the administrator password is asked for once, at the end, and only for a package
/// Apple signed. Once it is in, the system is started with the default kernel, which a
/// fresh install does not have yet.
@MainActor
final class ContainerInstallService: ObservableObject {
    enum State: Equatable {
        /// Nothing under way: the window offers the install.
        case idle
        /// Under way, at a named step, so the window can tick the steps off.
        case working(Step)
        /// Attempted and did not finish. Carries what to tell the user, which is never a raw
        /// networking or osascript error.
        case failed(String)
    }

    /// The stages of an install, in the order they happen.
    enum Step: Int, CaseIterable, Equatable {
        case downloading
        case verifying
        case installing
        case starting

        var title: String {
            switch self {
            case .downloading: return "Downloading container \(supportedContainerVersion)"
            case .verifying: return "Checking Apple's signature"
            case .installing: return "Installing"
            case .starting: return "Starting the container system"
            }
        }

        /// What the step is waiting on, when that is not obvious from its title.
        var note: String? {
            switch self {
            case .installing: return "Authorisation required"
            case .starting: return "Fetching the default kernel"
            default: return nil
            }
        }
    }

    @Published private(set) var state: State = .idle

    /// Start the container system once the install is in. Set by the owner.
    var onInstalled: () async -> Void = {}

    static let packageName = "container-\(supportedContainerVersion)-installer-signed.pkg"
    static let packageURL = URL(
        string: "https://github.com/apple/container/releases/download/\(supportedContainerVersion)/\(packageName)"
    )!
    /// Upstream's install instructions, for anyone who would rather do it by hand.
    static let instructionsURL = URL(string: "https://github.com/apple/container?tab=readme-ov-file#install-or-upgrade")!
    /// The team that signs container's pkg ("Developer ID Installer: Apple Inc. -
    /// Containerization"). The certificate chain alone only proves Apple issued a Developer
    /// ID; the team is what proves the package is Apple's own.
    static let signingTeamID = "UPBK2H6LZM"

    /// The commands the manual route runs, from a download of `packageName`.
    static let manualCommands = """
        sudo installer -pkg \(packageName) -target /
        container system start
        """

    typealias Download = @Sendable (_ from: URL, _ to: URL) async throws -> Void

    private let commandRunner: any CommandRunner
    private let fileManager: FileManager
    private let download: Download
    private var installTask: Task<Void, Never>?

    init(
        commandRunner: any CommandRunner = SystemCommandRunner(),
        fileManager: FileManager = .default,
        download: @escaping Download = ContainerInstallService.fetch
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.download = download
    }

    var currentStep: Step? {
        if case .working(let step) = state { return step }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Only the unprivileged steps can be abandoned. Once `installer` is running as root it
    /// finishes whatever happens to this task, and starting is the system's own lifecycle.
    var canCancel: Bool {
        currentStep == .downloading || currentStep == .verifying
    }

    /// Start an install, unless one is already running.
    func beginInstall() {
        guard installTask == nil else { return }
        installTask = Task { [weak self] in
            await self?.install()
            self?.installTask = nil
        }
    }

    func cancelInstall() {
        guard canCancel else { return }
        installTask?.cancel()
        installTask = nil
        state = .idle
    }

    private enum InstallError: Error {
        case badResponse
        case untrusted
        case installerFailed
    }

    /// Download, check, install, then start.
    func install() async {
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("orchard-container-install-\(UUID().uuidString)")
        let installed = await installPackage(in: scratch)
        try? fileManager.removeItem(at: scratch)
        guard installed else { return }

        state = .working(.starting)
        await onInstalled()
        // Whether or not the start worked, the window has moved on from "not installed":
        // to the containers when it did, and to the Start screen, with its diagnostics,
        // when it did not.
        state = .idle
    }

    /// Everything up to and including `installer`. True when the package is installed;
    /// otherwise `state` says why not.
    private func installPackage(in scratch: URL) async -> Bool {
        do {
            state = .working(.downloading)
            try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
            let package = scratch.appendingPathComponent(Self.packageName)
            try await download(Self.packageURL, package)

            try Task.checkCancellation()
            state = .working(.verifying)
            let signature = try await commandRunner.run(
                program: "/usr/sbin/pkgutil",
                arguments: ["--check-signature", package.path]
            )
            guard Self.isSignedByContainerTeam(signature) else { throw InstallError.untrusted }

            try Task.checkCancellation()
            state = .working(.installing)
            let result = try await commandRunner.runWithSudo(
                program: "/usr/sbin/installer",
                arguments: ["-pkg", package.path, "-target", "/"]
            )
            if result.failed {
                // The password prompt was dismissed: a decision, not a failure.
                if Self.wasAuthorisationCancelled(result) {
                    state = .idle
                    return false
                }
                throw InstallError.installerFailed
            }
            return true
        } catch is CancellationError {
            return false
        } catch InstallError.untrusted {
            state = .failed("The downloaded package is not signed by Apple, so it was not installed.")
        } catch InstallError.installerFailed {
            state = .failed("The installer did not finish.")
        } catch let error as URLError where error.code == .notConnectedToInternet {
            state = .failed("No network connection.")
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            state = .failed("container \(supportedContainerVersion) could not be downloaded.")
        }
        return false
    }

    /// True when `pkgutil --check-signature` says the package is signed, through a chain
    /// Apple issued, by the container team's Developer ID Installer certificate.
    nonisolated static func isSignedByContainerTeam(_ result: ProcessResult) -> Bool {
        guard !result.failed, let output = result.stdout else { return false }
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { $0.hasPrefix("Status: signed by a developer certificate issued by Apple") }) else {
            return false
        }
        // The leaf certificate is the first in the chain.
        guard let leaf = lines.first(where: { $0.hasPrefix("1. ") }) else { return false }
        return leaf.hasPrefix("1. Developer ID Installer: ") && leaf.hasSuffix("(\(signingTeamID))")
    }

    /// True when `do shell script ... with administrator privileges` failed because the
    /// prompt was dismissed (osascript's "User canceled", error -128).
    nonisolated static func wasAuthorisationCancelled(_ result: ProcessResult) -> Bool {
        let message = result.stderr ?? ""
        return message.contains("User canceled") || message.contains("-128")
    }

    nonisolated static func fetch(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("Orchard", forHTTPHeaderField: "User-Agent")

        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.badResponse
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
