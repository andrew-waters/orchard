import Foundation
import Testing
@testable import Orchard

// Tests for how `ComposePluginService` decides whether `container compose` works, and where
// an install goes. The CLI is asked rather than fixed paths checked (#113).

/// `container compose --version` from a Homebrew container 1.5.0 with no compose plugin.
private let homebrewMissing = """
    Error: unknown command 'compose'

    - If system services are not running, start them with: container system start

    If 'compose' is a plugin, check that it exists under:
      - /opt/homebrew/Cellar/container/1.5.0/libexec/container-plugins/compose
      - /opt/homebrew/Cellar/container/1.5.0/libexec/container/plugins/compose

    Usage: container [--debug] <subcommand>
      See 'container --help' for more information.
    """

@MainActor
@Test("Refresh: a working `container compose` is installed, with the version it reports")
func composePluginInstalledViaCLI() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: "0.4.0\n", stderr: nil) }
    let service = ComposePluginService(commandRunner: runner, containerBinaryPath: { "/opt/homebrew/bin/container" })

    await service.refresh()

    #expect(service.state == .installed(version: "0.4.0"))
    #expect(runner.calls.first == ["compose", "--version"])
}

@MainActor
@Test("Refresh: the CLI's unknown-command error is missing, and names where to install")
func composePluginMissingOnHomebrew() async {
    let runner = MockCommandRunner()
    runner.runHandler = { _, _ in ProcessResult(exitCode: 64, stdout: nil, stderr: homebrewMissing) }
    let service = ComposePluginService(commandRunner: runner, containerBinaryPath: { "/opt/homebrew/bin/container" })

    await service.refresh()

    // Missing even if an old copy sits in /usr/local, which this CLI never looks at: that
    // copy is what hid the reinstall offer in #113.
    #expect(service.isMissing)
    #expect(service.installPath == "/opt/homebrew/Cellar/container/1.5.0/libexec/container-plugins/compose")
}

@Test("Missing detection: both the 1.5.0 and the older wording, and nothing else")
func composePluginMissingWording() {
    #expect(ComposePluginService.indicatesMissingPlugin(homebrewMissing))
    #expect(ComposePluginService.indicatesMissingPlugin("Error: Plugin 'container-compose' not found."))
    #expect(!ComposePluginService.indicatesMissingPlugin("Error: Plugins are unavailable. Start the container system services and retry:"))
    #expect(!ComposePluginService.indicatesMissingPlugin("Error: unknown command 'k8s'"))
}

@Test("Search paths: read in order from the error, other hint lines ignored")
func composePluginSearchedDirectories() {
    #expect(ComposePluginService.searchedDirectories(inCLIError: homebrewMissing) == [
        "/opt/homebrew/Cellar/container/1.5.0/libexec/container-plugins/compose",
        "/opt/homebrew/Cellar/container/1.5.0/libexec/container/plugins/compose",
    ])
}

@Test("Plugin directories: derived from where the CLI really lives, so an update lands where it looks")
func composePluginDirectoriesFromBinary() {
    #expect(ComposePluginService.pluginDirectories(forContainerBinary: "/opt/homebrew/Cellar/container/1.6.1/bin/container") == [
        "/opt/homebrew/Cellar/container/1.6.1/libexec/container-plugins/compose",
        "/opt/homebrew/Cellar/container/1.6.1/libexec/container/plugins/compose",
    ])
    #expect(ComposePluginService.pluginDirectories(forContainerBinary: "/usr/local/bin/container") == ComposePluginService.defaultSearchPaths)
    #expect(ComposePluginService.pluginDirectories(forContainerBinary: "/Users/me/tools/container").isEmpty)
}

@Test("Privileges: a directory the user can write needs no prompt; a system one does")
func composePluginNeedsAdministrator() throws {
    let owned = FileManager.default.temporaryDirectory
        .appendingPathComponent("ComposePluginServiceTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: owned) }

    // Not created yet, like a fresh keg's plugin directory: judged by the nearest parent.
    #expect(!ComposePluginService.needsAdministrator(toWrite: owned.path + "/libexec/container-plugins/compose"))
    #expect(ComposePluginService.needsAdministrator(toWrite: "/System/Library/container-plugins/compose"))
}

// MARK: - Updates (#155)

@Test("Versions: dotted numbers parse, with an optional v; anything else does not")
func composePluginVersionParsing() {
    #expect(ComposePluginVersion("0.7.0")?.components == [0, 7, 0])
    #expect(ComposePluginVersion("v0.7.0")?.components == [0, 7, 0])
    #expect(ComposePluginVersion(" 0.7.0\n")?.components == [0, 7, 0])
    #expect(ComposePluginVersion("1.2")?.components == [1, 2])
    #expect(ComposePluginVersion("1.2.3.4")?.components == [1, 2, 3, 4])

    // A working-copy build reports this; it is not a release and is not compared.
    #expect(ComposePluginVersion("0.0.0-dev") == nil)
    #expect(ComposePluginVersion("0.7.0-rc.1") == nil)
    #expect(ComposePluginVersion("compose version 0.7.0") == nil)
    #expect(ComposePluginVersion("0..7") == nil)
    #expect(ComposePluginVersion("") == nil)
}

@Test("Versions: compared as numbers, missing components as zero")
func composePluginVersionOrdering() throws {
    let v = { (text: String) throws -> ComposePluginVersion in try #require(ComposePluginVersion(text)) }
    #expect(try v("0.10.0") > v("0.9.0"))
    #expect(try v("1.0.0") > v("0.99.99"))
    #expect(try v("0.7.1") > v("0.7"))
    #expect(try v("0.7") == v("0.7.0"))
    #expect(try !(v("0.7.0") < v("v0.7.0")))
}

@Test("Offer: a newer release is offered; the latest or newer installed is not")
func composePluginUpdateAgainstLatest() {
    #expect(ComposePluginService.updateOffer(installed: "0.6.0", latest: "0.7.0", linked: "0.7.0") == .newerRelease("0.7.0"))
    #expect(ComposePluginService.updateOffer(installed: "0.9.0", latest: "0.10.0", linked: "0.7.0") == .newerRelease("0.10.0"))
    #expect(ComposePluginService.updateOffer(installed: "0.7.0", latest: "0.7.0", linked: "0.7.0") == nil)
    #expect(ComposePluginService.updateOffer(installed: "0.8.0", latest: "0.7.0", linked: "0.7.0") == nil)
}

@Test("Offer: with no latest release known, a plugin older than Orchard's package is still offered")
func composePluginUpdateAgainstLinked() {
    #expect(ComposePluginService.updateOffer(installed: "0.6.0", latest: nil, linked: "0.7.0") == .olderThanOrchard("0.7.0"))
    #expect(ComposePluginService.updateOffer(installed: "0.7.0", latest: nil, linked: "0.7.0") == nil)
    // An unreadable latest counts as unknown, not as newer.
    #expect(ComposePluginService.updateOffer(installed: "0.6.0", latest: "nightly", linked: "0.7.0") == .olderThanOrchard("0.7.0"))
    #expect(ComposePluginService.updateOffer(installed: "0.7.0", latest: "nightly", linked: "0.7.0") == nil)
}

@Test("Offer: an installed version that does not parse is left alone")
func composePluginUpdateUnparseable() {
    #expect(ComposePluginService.updateOffer(installed: "0.0.0-dev", latest: "0.7.0", linked: "0.7.0") == nil)
    #expect(ComposePluginService.updateOffer(installed: "unknown", latest: nil, linked: "0.7.0") == nil)
}

@Test("Linked version: matches the compose pin in Package.resolved")
func composePluginLinkedVersionMatchesPin() throws {
    let resolved = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Orchard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")

    struct Resolved: Decodable {
        struct Pin: Decodable {
            struct State: Decodable { let version: String? }
            let identity: String
            let state: State
        }
        let pins: [Pin]
    }

    let pins = try JSONDecoder().decode(Resolved.self, from: Data(contentsOf: resolved)).pins
    let compose = try #require(pins.first { $0.identity == "compose" })
    #expect(compose.state.version == ComposePluginService.linkedVersion)
}

/// Answers every request with one canned reply. Serialised below, since the reply is shared.
private final class ReleaseStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session(status: Int, body: String) -> URLSession {
        self.status = status
        self.body = Data(body.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseStubProtocol.self]
        return URLSession(configuration: config)
    }
}

@MainActor
@Suite("Update lookup", .serialized)
struct ComposePluginUpdateLookupTests {
    private func service(session: URLSession) -> ComposePluginService {
        let runner = MockCommandRunner()
        runner.runHandler = { _, _ in ProcessResult(exitCode: 0, stdout: "0.6.0\n", stderr: nil) }
        return ComposePluginService(commandRunner: runner, session: session, containerBinaryPath: { "/usr/local/bin/container" })
    }

    @Test("A published release is recorded and offered over 0.6.0")
    func recordsLatest() async {
        let body = """
            {"tag_name": "0.7.0", "assets": [{"name": "compose-0.7.0-macos-arm64.tar.gz",
              "browser_download_url": "https://example.com/compose-0.7.0-macos-arm64.tar.gz"}]}
            """
        let service = service(session: ReleaseStubProtocol.session(status: 200, body: body))

        await service.refresh()
        await service.checkForUpdate()

        #expect(service.latestVersion == "0.7.0")
        #expect(service.update == .newerRelease("0.7.0"))
    }

    @Test("A failed lookup leaves the latest unknown, falling back to Orchard's package")
    func failedLookupIsUnknown() async {
        let service = service(session: ReleaseStubProtocol.session(status: 403, body: "rate limited"))

        await service.refresh()
        await service.checkForUpdate()

        #expect(service.latestVersion == nil)
        #expect(service.state == .installed(version: "0.6.0"))
        #expect(service.update == .olderThanOrchard(ComposePluginService.linkedVersion))
    }
}
