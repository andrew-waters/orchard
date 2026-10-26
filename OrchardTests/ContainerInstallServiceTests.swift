import Foundation
import Testing
@testable import Orchard

// Tests for installing Apple container when it is missing (#145): what is trusted, what runs
// as root, and what happens when the user or the network says no.

/// `pkgutil --check-signature` on the 1.6.0 release's signed pkg.
private let signedOutput = """
    Package "container-1.6.0-installer-signed.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Notarization: trusted by the Apple notary service
       Signed with a trusted timestamp on: 2026-10-20 19:34:34 +0000
       Certificate Chain:
        1. Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)
           Expires: 2030-06-04 16:44:29 +0000
           ------------------------------------------------------------------------
        2. Developer ID Certification Authority
           Expires: 2031-09-17 00:00:00 +0000
           ------------------------------------------------------------------------
        3. Apple Root CA
           Expires: 2035-02-09 21:40:36 +0000
    """

/// A valid Developer ID signature, but not the container team's.
private let otherTeamOutput = signedOutput
    .replacingOccurrences(of: "Apple Inc. - Containerization (UPBK2H6LZM)", with: "Someone Else (ABCDE12345)")

/// Writes a stand-in package, and remembers where, so a test can check it was cleaned up.
private final class FakeDownload: @unchecked Sendable {
    private let lock = NSLock()
    private var _destination: URL?
    var destination: URL? { lock.withLock { _destination } }
    var error: Error?

    func callAsFunction(_ from: URL, _ to: URL) async throws {
        lock.withLock { _destination = to }
        if let error { throw error }
        try Data("pkg".utf8).write(to: to)
    }
}

@MainActor
private func makeInstaller(
    runner: MockCommandRunner,
    download: FakeDownload = FakeDownload()
) -> (ContainerInstallService, started: () -> Bool) {
    let service = ContainerInstallService(commandRunner: runner, download: { try await download($0, $1) })
    var started = false
    service.onInstalled = { started = true }
    return (service, { started })
}

/// A runner that answers pkgutil with `signature` and the privileged install script with
/// `installer`.
private func fakeRunner(signature: ProcessResult, installer: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: nil)) -> MockCommandRunner {
    let runner = MockCommandRunner()
    runner.runHandler = { program, _ in
        switch program {
        case "/usr/sbin/pkgutil": return signature
        case "/bin/sh": return installer
        default: return ProcessResult(exitCode: 0, stdout: "", stderr: nil)
        }
    }
    return runner
}

private let signed = ProcessResult(exitCode: 0, stdout: signedOutput, stderr: nil)

@Test("Signature: only the container team's Developer ID Installer certificate is trusted")
func containerInstallSignature() {
    #expect(ContainerInstallService.isSignedByContainerTeam(signed))
    #expect(!ContainerInstallService.isSignedByContainerTeam(ProcessResult(exitCode: 0, stdout: otherTeamOutput, stderr: nil)))
    #expect(!ContainerInstallService.isSignedByContainerTeam(
        ProcessResult(exitCode: 1, stdout: "Package \"x.pkg\":\n   Status: no signature\n", stderr: nil)))
    #expect(!ContainerInstallService.isSignedByContainerTeam(ProcessResult(exitCode: 1, stdout: signedOutput, stderr: nil)))
}

@Test("Package: the pinned release's signed pkg")
func containerInstallPackageURL() {
    #expect(ContainerInstallService.packageURL.absoluteString
        == "https://github.com/apple/container/releases/download/\(supportedContainerVersion)/container-\(supportedContainerVersion)-installer-signed.pkg")
}

@Test("Privileged script: a package that fails the check never reaches installer")
func containerInstallPrivilegedScriptRejects() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ContainerInstallServiceTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = directory.appendingPathComponent("container.pkg")
    try Data("not a package".utf8).write(to: package)

    // Unprivileged, and safe to run for real: the script stops before `installer`.
    let result = try await SystemCommandRunner().run(
        program: "/bin/sh",
        arguments: ["-c", ContainerInstallService.privilegedInstallScript, "sh", package.path])

    #expect(result.exitCode == 3)
    #expect(result.stderr?.contains(ContainerInstallService.untrustedMarker) == true)
}

@MainActor
@Test("Install: checks the signature, runs installer as root, then starts the system")
func containerInstallHappyPath() async {
    let runner = fakeRunner(signature: signed)
    let download = FakeDownload()
    let (service, started) = makeInstaller(runner: runner, download: download)

    await service.install()

    let package = download.destination?.path
    #expect(runner.calls == [
        ["--check-signature", package ?? ""],
        ["-c", ContainerInstallService.privilegedInstallScript, "sh", package ?? ""],
    ])
    #expect(started())
    #expect(service.state == .idle)
    #expect(!FileManager.default.fileExists(atPath: package ?? ""))
}

@MainActor
@Test("Install: a package from anyone else never reaches installer")
func containerInstallUntrusted() async {
    let runner = fakeRunner(signature: ProcessResult(exitCode: 0, stdout: otherTeamOutput, stderr: nil))
    let (service, started) = makeInstaller(runner: runner)

    await service.install()

    #expect(runner.calls.count == 1)
    #expect(service.failureMessage != nil)
    #expect(!started())
}

@MainActor
@Test("Install: a package swapped after the first check is reported, and nothing starts")
func containerInstallUntrustedAsRoot() async {
    let runner = fakeRunner(
        signature: signed,
        installer: ProcessResult(exitCode: 1, stdout: nil, stderr: "execution error: \(ContainerInstallService.untrustedMarker) (3)"))
    let (service, started) = makeInstaller(runner: runner)

    await service.install()

    #expect(service.failureMessage == "The downloaded package is not signed by Apple, so it was not installed.")
    #expect(!started())
}

@MainActor
@Test("Install: dismissing the password prompt is declined, not an error")
func containerInstallPromptDismissed() async {
    let runner = fakeRunner(
        signature: signed,
        installer: ProcessResult(exitCode: 1, stdout: nil, stderr: "execution error: User canceled. (-128)"))
    let (service, started) = makeInstaller(runner: runner)

    await service.install()

    #expect(service.state == .declined)
    #expect(service.failureMessage == nil)
    #expect(!started())
}

@MainActor
@Test("Install: a failed installer is reported and does not start the system")
func containerInstallInstallerFails() async {
    let runner = fakeRunner(
        signature: signed,
        installer: ProcessResult(exitCode: 1, stdout: nil, stderr: "installer: Error - the package path specified was invalid"))
    let (service, started) = makeInstaller(runner: runner)

    await service.install()

    #expect(service.failureMessage == "The installer did not finish.")
    #expect(!started())
}

@MainActor
@Test("Install: no network is said plainly, nothing runs, and the scratch file is gone")
func containerInstallOffline() async {
    let runner = fakeRunner(signature: signed)
    let download = FakeDownload()
    download.error = URLError(.notConnectedToInternet)
    let (service, started) = makeInstaller(runner: runner, download: download)

    await service.install()

    #expect(service.failureMessage == "No network connection.")
    #expect(runner.calls.isEmpty)
    #expect(!started())
    let scratch = download.destination?.deletingLastPathComponent().path ?? ""
    #expect(!FileManager.default.fileExists(atPath: scratch))
}
