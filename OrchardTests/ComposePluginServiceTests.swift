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
