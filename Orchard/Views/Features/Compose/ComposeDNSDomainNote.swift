import AppKit
import SwiftUI

/// What the Compose tab says about the DNS domain its containers are created under.
///
/// Orchard creates compose containers under its own default domain (Settings > General > DNS
/// Domain), which falls back to the daemon's `dns.domain`. `container compose` in a terminal
/// reads only the daemon's, and the CLI can no longer write it (#116), so the two can differ.
/// When they do, the tab says so, since a project brought up in a terminal would then answer
/// to other names.
struct ComposeDNSDomainWording: Equatable {
    /// The domain in one line: what services resolve as, or that they cannot.
    let summary: String
    /// Set when the terminal plugin would use another domain.
    let terminalDifference: String?

    /// - Parameters:
    ///   - orchard: the domain Orchard creates compose containers under (`DNSService.defaultDomain`).
    ///   - daemon: the daemon's `dns.domain` from `config.toml`, which `container compose` uses.
    init(orchard: String?, daemon: String?) {
        let orchard = orchard.flatMap { $0.isEmpty ? nil : $0 }
        let daemon = daemon.flatMap { $0.isEmpty ? nil : $0 }
        if let orchard {
            summary = "Services resolve as <container>.\(orchard)"
        } else {
            summary = "No DNS domain, so services can't reach each other by name"
        }
        if orchard == daemon {
            terminalDifference = nil
        } else if let daemon {
            terminalDifference = "`container compose` in a terminal uses \(daemon) instead"
        } else {
            terminalDifference = "`container compose` in a terminal uses no domain"
        }
    }

    static let explanation = "Orchard creates compose containers under the DNS domain chosen in "
        + "Settings, or container's default when none is chosen. `container compose` in a terminal "
        + "always uses container's default from config.toml, which Orchard can't change. "
        + "Containers pick up a new domain when they are next recreated."
}

/// The domain line at the foot of the Compose tab, with a way to change it.
struct ComposeDNSDomainNote: View {
    @EnvironmentObject var dnsService: DNSService
    // Observed so the line follows a change of domain in Settings, and the daemon's own.
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var systemService: SystemService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let wording = ComposeDNSDomainWording(
            orchard: dnsService.defaultDomain,
            daemon: dnsService.daemonDefaultDomain()
        )
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(wording.summary)
                if let difference = wording.terminalDifference {
                    Text(.init(difference))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(ComposeDNSDomainWording.explanation)

            Spacer(minLength: 4)

            Button("Change in Settings") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}
