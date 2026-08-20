import Foundation

/// Owns DNS domain state and operations, backed by the `container system dns` CLI
/// (create/delete require sudo). The default domain is a system property, so this reads
/// and writes it through closures the owner wires to the system service.
@MainActor
final class DNSService: ObservableObject {
    @Published var dnsDomains: [DNSDomain] = []
    @Published var isDNSLoading = false

    private let runner: CommandRunner
    private let settings: SettingsStore
    private let alertCenter: AlertCenter

    /// Refresh the system properties (which hold the default domain). Set by the owner.
    var refreshSystemProperties: () async -> Void = {}
    /// The current default domain from system properties. Set by the owner.
    var defaultDomain: @MainActor () -> String? = { nil }
    /// Optimistically record `domain` as the default system property. Set by the owner.
    var setDefaultDomainProperty: @MainActor (String) -> Void = { _ in }

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
                dnsDomains = parseDNSDomains(json: output, defaultDomain: defaultDomain())
            }
        } catch {
            if showLoading {
                alertCenter.error("Failed to load DNS domains: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func create(_ domain: String) async -> Bool {
        do {
            let result = try await runner.runWithSudo(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "dns", "create", domain])

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
        if defaultDomain() == domain {
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

    /// Optimistically mark `domain` as the default in the local list.
    func markDefault(_ domain: String) {
        for i in dnsDomains.indices {
            dnsDomains[i] = DNSDomain(domain: dnsDomains[i].domain, isDefault: dnsDomains[i].domain == domain)
        }
    }

    func setDefault(_ domain: String) async {
        // Optimistic UI update.
        setDefaultDomainProperty(domain)
        markDefault(domain)

        do {
            let result = try await runner.run(
                program: settings.safeContainerBinaryPath(),
                arguments: ["system", "property", "set", "dns.domain", domain])

            if result.failed {
                await refreshSystemProperties()
                await load(showLoading: false)
                alertCenter.error(result.stderr ?? "Failed to set default DNS domain")
            }
        } catch {
            await refreshSystemProperties()
            await load(showLoading: false)
            alertCenter.error("Failed to set default DNS domain: \(error.localizedDescription)")
        }
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
