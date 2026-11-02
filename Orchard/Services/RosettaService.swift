import Foundation
import Virtualization

/// Whether this Mac can run linux/amd64 containers, which Apple container does under Rosetta.
enum RosettaAvailability: Equatable, Sendable {
    case installed
    /// Apple silicon without Rosetta yet: it can be installed.
    case notInstalled
    /// An Intel Mac, or one Rosetta cannot run on: there is nothing to install.
    case notSupported

    /// What the Virtualization framework reports right now. Cheap: it reads local state.
    static var current: RosettaAvailability {
        #if arch(arm64)
        switch VZLinuxRosettaDirectoryShare.availability {
        case .installed: return .installed
        case .notInstalled: return .notInstalled
        case .notSupported: return .notSupported
        @unknown default: return .notSupported
        }
        #else
        // The framework's Rosetta API only exists on Apple silicon, and an Intel Mac has no
        // Rosetta to install, so the Intel half of the universal build says so directly.
        return .notSupported
        #endif
    }

    /// Install Rosetta through the Virtualization framework. An Intel Mac can't, as above.
    static func install() async throws {
        #if arch(arm64)
        try await VZLinuxRosettaDirectoryShare.installRosetta()
        #else
        throw RosettaNotSupported()
        #endif
    }
}

/// Rosetta asked for on a Mac that can't run it.
struct RosettaNotSupported: LocalizedError {
    var errorDescription: String? { "Rosetta only runs on Apple silicon." }
}

/// Reports and installs Rosetta for the Run and Edit sheets (#147), so choosing an amd64
/// platform without it is caught before anything is created rather than as a failure from
/// the runtime once the image has been fetched.
@MainActor
final class RosettaService: ObservableObject {
    @Published private(set) var availability: RosettaAvailability
    @Published private(set) var isInstalling = false
    /// Why the last install did not finish, or nil.
    @Published private(set) var installError: String?

    private let probe: @Sendable () -> RosettaAvailability
    private let installer: @Sendable () async throws -> Void

    init(
        probe: @escaping @Sendable () -> RosettaAvailability = { RosettaAvailability.current },
        installer: @escaping @Sendable () async throws -> Void = { try await RosettaAvailability.install() }
    ) {
        self.probe = probe
        self.installer = installer
        self.availability = probe()
    }

    func refresh() {
        availability = probe()
    }

    /// Installs Rosetta. macOS shows its own licence prompt; declining it is reported like
    /// any other failure, with the command to do it by hand.
    func install() async {
        guard !isInstalling else { return }
        isInstalling = true
        installError = nil
        defer { isInstalling = false }
        do {
            try await installer()
        } catch {
            installError = "Rosetta was not installed: \(error.localizedDescription) "
                + "It can also be installed with `softwareupdate --install-rosetta`."
        }
        refresh()
    }
}
