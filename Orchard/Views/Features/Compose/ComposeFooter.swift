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
    /// The domain, or that there is none.
    let label: String
    /// Whether there is a domain at all. Without one, services can't reach each other by name.
    let hasDomain: Bool
    /// Set when the terminal plugin would use another domain.
    let terminalDifference: String?
    /// The longer explanation, for the tooltip.
    let explanation: String

    /// - Parameters:
    ///   - orchard: the domain Orchard creates compose containers under (`DNSService.defaultDomain`).
    ///   - daemon: the daemon's `dns.domain` from `config.toml`, which `container compose` uses.
    init(orchard: String?, daemon: String?) {
        let orchard = orchard.flatMap { $0.isEmpty ? nil : $0 }
        let daemon = daemon.flatMap { $0.isEmpty ? nil : $0 }
        hasDomain = orchard != nil
        label = orchard.map { "Default domain: \($0)" } ?? "No default domain"
        if orchard == daemon {
            terminalDifference = nil
        } else {
            terminalDifference = "In a terminal: \(daemon ?? "no domain")"
        }

        var text = orchard.map { "Services resolve as <container>.\($0)." }
            ?? "With no DNS domain, services can't reach each other by name."
        text += " Orchard uses the DNS domain chosen in Settings, or container's default when "
            + "none is chosen. `container compose` in a terminal always uses container's default "
            + "from config.toml, which Orchard can't change. Containers pick up a new domain "
            + "when they are next recreated. Click to change it in Settings."
        explanation = text
    }
}

/// The foot of the Compose tab: the installed plugin's version, linking to its release, and
/// the DNS domain compose containers get, which opens Settings to change it.
struct ComposeFooter: View {
    /// What the installed plugin reports, or nil when none is found.
    let installedVersion: String?

    @EnvironmentObject var dnsService: DNSService
    // Observed so the domain follows a change in Settings, and the daemon's own.
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var systemService: SystemService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let wording = ComposeDNSDomainWording(
            orchard: dnsService.defaultDomain,
            daemon: dnsService.daemonDefaultDomain()
        )
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if let installedVersion {
                    Link(destination: ComposePluginVersion.pageURL(for: installedVersion)) {
                        Text(ComposePluginVersion.displayed(installedVersion))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Color.accentColor)
                    // The full version, commit and all, for a development build.
                    .help("container compose \(installedVersion): open its release on GitHub")
                }
                // With no plugin installed, the banner at the top of the tab says so.
                Spacer(minLength: 8)
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Label(wording.label, systemImage: wording.hasDomain ? "network" : "exclamationmark.triangle")
                        .lineLimit(1)
                        .foregroundStyle(wording.hasDomain ? Color.accentColor : Color.orange)
                }
                .buttonStyle(.borderless)
                .help(wording.explanation)
            }
            if let difference = wording.terminalDifference {
                Label(difference, systemImage: "terminal")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(wording.explanation)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
