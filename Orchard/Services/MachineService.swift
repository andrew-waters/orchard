import Foundation

/// Owns container-machine state and lifecycle, backed by the machine XPC client. Mirrors the
/// other per-domain services: `@Published` state, `AlertCenter` for user-facing errors, and a
/// `load()` that the app's refresh loop calls. Machines never enter the container god object.
@MainActor
final class MachineService: ObservableObject {
    @Published var machines: [Machine] = []
    @Published var isLoading = false
    /// True when the machine API server is unreachable — typically a `container` install that
    /// predates machine support. Drives an explanatory empty state instead of an error alert.
    @Published var apiUnavailable = false

    private let backend: MachineBackend
    private let alertCenter: AlertCenter

    init(backend: MachineBackend, alertCenter: AlertCenter) {
        self.backend = backend
        self.alertCenter = alertCenter
    }

    func load(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }

        do {
            let machines = try await backend.listMachines()
            if machines != self.machines {
                self.machines = machines
            }
            self.apiUnavailable = false
            self.isLoading = false
        } catch OrchardError.machineApiUnavailable {
            // Expected on installs without machine support: show the empty state, never alert.
            self.apiUnavailable = true
            self.machines = []
            self.isLoading = false
        } catch {
            if showLoading {
                self.alertCenter.error("Failed to load machines: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }

    /// Whether a create is in flight — drives the create form's spinner and disables re-submit.
    @Published var isCreating = false

    @discardableResult
    func create(_ spec: MachineCreateSpec) async -> Bool {
        isCreating = true
        defer { isCreating = false }
        do {
            try await backend.createMachine(spec)
            await load(showLoading: false)
            return true
        } catch {
            self.alertCenter.error("Failed to create machine: \(error.localizedDescription)")
            return false
        }
    }

    /// Apply an edited boot config. `setConfig` only takes effect on the next boot; when
    /// `restartNow` is set (offered while running), stop-then-boot so the change goes live in
    /// one action — the differentiator over the CLI's manual stop/restart.
    @discardableResult
    func applyConfig(_ config: MachineConfigSpec, to id: String, restartNow: Bool) async -> Bool {
        do {
            try await backend.setMachineConfig(id: id, config: config)
            if restartNow {
                // Ignore a stop error (already stopped); the boot is what makes the change live.
                try? await backend.stopMachine(id: id)
                try await backend.bootMachine(id: id)
            }
            await load(showLoading: false)
            return true
        } catch {
            self.alertCenter.error("Failed to update machine: \(error.localizedDescription)")
            return false
        }
    }

    func boot(_ id: String) async {
        do {
            try await backend.bootMachine(id: id)
            await load(showLoading: false)
        } catch {
            self.alertCenter.error("Failed to start machine: \(error.localizedDescription)")
        }
    }

    func stop(_ id: String) async {
        do {
            try await backend.stopMachine(id: id)
            await load(showLoading: false)
        } catch {
            self.alertCenter.error("Failed to stop machine: \(error.localizedDescription)")
        }
    }

    func delete(_ id: String) async {
        do {
            try await backend.deleteMachine(id: id)
            await load(showLoading: false)
        } catch {
            self.alertCenter.error("Failed to delete machine: \(error.localizedDescription)")
        }
    }

    func setDefault(_ id: String) async {
        do {
            try await backend.setDefaultMachine(id: id)
            await load(showLoading: false)
        } catch {
            self.alertCenter.error("Failed to set default machine: \(error.localizedDescription)")
        }
    }

    /// Read a machine's logs as text lines. `logs(id:)` returns `[stdio, boot]` file handles
    /// (confirmed in the M0 spike); `boot: true` selects the VM boot log.
    func fetchLogs(id: String, boot: Bool = false, tailLines: Int = 5000) async throws -> [String] {
        let handles = try await backend.machineLogs(id: id)
        let handle: FileHandle? = boot ? (handles.count > 1 ? handles[1] : handles.first) : handles.first
        guard let handle else { return [] }

        return try await Task.detached {
            let data = handle.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return [String]() }
            let lines = text.components(separatedBy: "\n")
            if lines.count > tailLines {
                return Array(lines.suffix(tailLines))
            }
            return lines
        }.value
    }
}
