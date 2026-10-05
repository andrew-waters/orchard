import Foundation

/// Owns DNS domain state and operations, backed by the `container system dns` CLI
/// (create/delete require sudo). The default domain is an Orchard preference: the CLI can
/// no longer write the daemon's `dns.domain` (#116), so the daemon's value, read through a
/// closure the owner wires to the system service, only stands in when none is chosen.
@MainActor
final class DNSService: ObservableObject {
    @Published var dnsDomains: [DNSDomain] = []
    @Published var isDNSLoading = false

    private let runner: CommandRunner
    private let settings: SettingsStore
    private let alertCenter: AlertCenter
    /// Where the CLI writes one resolver file per domain. Overridable for tests.
    var resolverDirectory = URL(fileURLWithPath: "/etc/resolver")

    /// Refresh the system properties (which hold the daemon's default domain). Set by the owner.
    var refreshSystemProperties: () async -> Void = {}
    /// The daemon's `dns.domain`, from `config.toml`. Set by the owner.
    var daemonDefaultDomain: @MainActor () -> String? = { nil }

    /// The domain new containers get by default: the one chosen in Orchard, else the daemon's.
    var defaultDomain: String? {
        settings.defaultDNSDomain ?? daemonDefaultDomain()
    }

    init(runner: CommandRunner, settings: SettingsStore, alertCenter: AlertCenter) {
        self.runner = runner
        self.settings = settings
        self.alertCenter = alertCenter
    }

    func load(showLoading: Bool = true) async {
        if showLoading {
            isDNSLoading = true
            alertCenter.dismiss()
        }
        defer { isDNSLoading = false }   // clear on every exit path, incl. nil-stdout

        // The default domain comes from system properties. Only pay for a full refresh on
        // user-initiated loads; background polls reuse the already-cached value.
        if showLoading {
            await refreshSystemProperties()
        }

        do {
            let listResult = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "dns", "ls", "--format=json"])

            if listResult.failed {
                // Leave the existing domains untouched rather than blanking them; only
                // alert when the user asked for this load, not on a background refresh.
                if showLoading {
                    alertCenter.error(listResult.stderr ?? "Failed to load DNS domains")
                }
                return
            }

            if let output = listResult.stdout {
                let parsed = parseDNSDomains(json: output, defaultDomain: nil)
                // A chosen default deleted outside Orchard would otherwise stay chosen and
                // hide the daemon's.
                if let chosen = settings.defaultDNSDomain, !parsed.contains(where: { $0.domain == chosen }) {
                    settings.setDefaultDNSDomain(nil)
                }
                dnsDomains = parsed.map { withLocalhostRedirect(markedDefault($0)) }
            }
        } catch {
            if showLoading {
                alertCenter.error("Failed to load DNS domains: \(error.localizedDescription)")
            }
        }
    }

    /// The domain with its localhost redirect filled in from its resolver file, which is
    /// world-readable, so this needs no sudo. A missing or unreadable file means no redirect.
    private func withLocalhostRedirect(_ domain: DNSDomain) -> DNSDomain {
        let file = resolverDirectory.appendingPathComponent("containerization.\(domain.domain)")
        guard let config = try? String(contentsOf: file, encoding: .utf8),
              let redirect = parseLocalhostRedirect(resolverConfig: config)
        else { return domain }
        return DNSDomain(domain: domain.domain, isDefault: domain.isDefault, localhostRedirect: redirect)
    }

    private func markedDefault(_ domain: DNSDomain) -> DNSDomain {
        DNSDomain(domain: domain.domain, isDefault: domain.domain == defaultDomain,
                  localhostRedirect: domain.localhostRedirect)
    }

    /// `localhost` makes the domain resolve to that IPv4 address and has pf redirect it to
    /// the Mac's 127.0.0.1, so containers can reach services bound to the host's loopback.
    /// Before container 1.5.0 adding or removing that rule reloaded all of pf and cut every
    /// running container's outbound networking (apple/container#2256).
    @discardableResult
    func create(_ domain: String, localhost: String? = nil) async -> Bool {
        var arguments = ["system", "dns", "create", domain]
        if let localhost, !localhost.isEmpty { arguments += ["--localhost", localhost] }
        do {
            let result = try await runner.runWithSudo(
                program: settings.safeContainerBinaryPath(),
                arguments: arguments)

            if !result.failed {
                await load()
                return true
            } else {
                alertCenter.error(result.stderr ?? "Failed to create DNS domain")
                return false
            }
        } catch {
            alertCenter.error("Failed to create DNS domain: \(error.localizedDescription)")
            return false
        }
    }

    func delete(_ domain: String) async {
        if defaultDomain == domain {
            alertCenter.error("Cannot delete the default DNS domain.")
            return
        }

        do {
            let result = try await runner.runWithSudo(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "dns", "delete", domain])

            if !result.failed {
                await load()
            } else {
                alertCenter.error(result.stderr ?? "Failed to delete DNS domain")
            }
        } catch {
            alertCenter.error("Failed to delete DNS domain: \(error.localizedDescription)")
        }
    }

    /// Make `domain` the default for containers Orchard creates; nil goes back to the
    /// daemon's. Stored as a preference, so there is nothing to run and nothing to fail.
    func setDefault(_ domain: String?) {
        settings.setDefaultDNSDomain(domain)
        dnsDomains = dnsDomains.map(markedDefault)
    }
    func deleteDNSDomains(_ domains: [String]) async {
        guard !domains.isEmpty else { return }
        
        let script = """
        for d in "$@"; do
            err=$("$0" system dns delete "$d" 2>&1 >/dev/null)
            if [ $? -ne 0 ]; then
                echo "FAILED|$d|$err"
            fi
        done
        """
        
        do {
            let arguments = ["-c", script, settings.safeContainerBinaryPath()] + domains
            let result = try await runner.runWithSudo(program: "/bin/sh", arguments: arguments)
            
            var failedDetails = [String]()
            let lines = (result.stdout ?? "").components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            for line in lines {
                if line.hasPrefix("FAILED|") {
                    let parts = line.split(separator: "|", maxSplits: 2)
                    if parts.count == 3 {
                        failedDetails.append("\(parts[1]): \(parts[2])")
                    }
                }
            }
            
            await load()
            if !failedDetails.isEmpty {
                alertCenter.error("Failed to delete domains:\n" + failedDetails.joined(separator: "\n"))
            } else if result.failed {
                alertCenter.error(result.stderr ?? "Failed to delete DNS domains")
            }
        } catch {
            await load()
            alertCenter.error("Failed to delete DNS domains: \(error.localizedDescription)")
        }
    }
}
