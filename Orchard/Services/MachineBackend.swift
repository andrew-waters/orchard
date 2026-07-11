import Foundation
import ArgumentParser
import MachineAPIClient
import ContainerAPIClient
import ContainerResource
import ContainerPersistence
import ContainerizationOCI

// MARK: - Boundary value types

/// Everything needed to create a container machine, in app-owned types so the backend
/// boundary never leaks the client's config types. `memoryGiB`/`cpus`/`homeMount` nil means
/// "use the runtime default" (memory defaults to half of host RAM).
struct MachineCreateSpec: Sendable {
    let name: String
    let imageRef: String
    let cpus: Int?
    let memoryGiB: Int?
    /// `ro` / `rw` / `none`, or nil for the default (`rw`).
    let homeMount: String?
    let virtualization: Bool
    let kernelPath: String?
    let setDefault: Bool
    let noBoot: Bool
}

/// Editable boot-time configuration for an existing machine. Applied via `setConfig`, which
/// only takes effect on the next boot (the service can orchestrate a restart).
struct MachineConfigSpec: Sendable {
    let cpus: Int
    let memoryGiB: Int
    let homeMount: String
    let virtualization: Bool
    let kernelPath: String?
}

// MARK: - Backend protocol

/// The container-machine runtime surface, expressed entirely in app domain models. Mocks
/// conforming to this need no client-package imports. Mirrors `ContainerBackend`'s design
/// rule: no package types cross this boundary.
protocol MachineBackend: Sendable {
    func listMachines() async throws -> [Machine]
    func inspectMachine(id: String) async throws -> Machine
    func createMachine(_ spec: MachineCreateSpec) async throws
    /// Update a machine's boot config. Takes effect on the next boot.
    func setMachineConfig(id: String, config: MachineConfigSpec) async throws
    func bootMachine(id: String) async throws
    func stopMachine(id: String) async throws
    /// Delete a machine. This removes its persistent storage.
    func deleteMachine(id: String) async throws
    func setDefaultMachine(id: String) async throws
    func machineLogs(id: String) async throws -> [FileHandle]
}

// MARK: - Live implementation

/// `MachineBackend` backed by the real machine XPC client (`MachineClient`, talking to the
/// separate `com.apple.container.core.machine-apiserver` Mach service), translating the
/// client's `MachineSnapshot` to the app's `Machine` model.
struct LiveMachineBackend: MachineBackend {
    func listMachines() async throws -> [Machine] {
        let client = MachineClient()
        do {
            let snapshots = try await client.list()
            // The default machine comes from a separate route; a failure there only costs
            // the "default" badge, so it must not fail the whole list.
            let defaultId = try? await client.getDefault()
            return snapshots.map { mapMachine($0, isDefault: $0.id == defaultId) }
        } catch {
            throw mapMachineError(error)
        }
    }

    func inspectMachine(id: String) async throws -> Machine {
        let client = MachineClient()
        do {
            let snapshot = try await client.inspect(id: id)
            let defaultId = try? await client.getDefault()
            return mapMachine(snapshot, isDefault: snapshot.id == defaultId)
        } catch {
            throw mapMachineError(error)
        }
    }

    func createMachine(_ spec: MachineCreateSpec) async throws {
        do {
            // Validate a custom kernel path up front for a clean error (mirrors the CLI).
            if let kernelPath = spec.kernelPath, !kernelPath.isEmpty {
                _ = try MachineConfig.validateKernelPath(kernelPath)
            }

            let systemConfig = try await ConfigurationLoader.load()
            // Start from the system default machine config and apply the user's overrides.
            let bootConfig = try systemConfig.machine.with([
                "cpus": spec.cpus.map { "\($0)" },
                "memory": spec.memoryGiB.map { "\($0)G" },
                "home-mount": spec.homeMount,
                // Emit explicitly (not nil) so unchecking nested virtualization disables it
                // rather than falling back to the system default.
                "virtualization": spec.virtualization ? "true" : "false",
                "kernel": spec.kernelPath,
            ].compactMapValues { $0 })

            let client = MachineClient()
            // These are ArgumentParser types: their @Option/@Flag defaults are only populated
            // by parsing, so `parse([])` (no args) yields an instance with every default filled
            // — reading a field off a bare `init()` instance traps ("Can't read a value from a
            // parsable argument definition"). We want exactly the defaults here.
            let management = try Flags.MachineManagement.parse([])
            let registry = try Flags.Registry.parse([])
            let imageFetch = try Flags.ImageFetch.parse([])

            // Fetch + unpack the image and build the machine configuration. Progress is
            // ignored here; the UI shows its own creating state.
            let (config, resources) = try await MachineClient.machineConfigFromFlags(
                id: spec.name,
                image: spec.imageRef,
                management: management,
                registry: registry,
                imageFetch: imageFetch,
                containerSystemConfig: systemConfig,
                progressUpdate: { _ in }
            )

            try await client.create(configuration: config, resources: resources, bootConfig: bootConfig)

            if spec.setDefault {
                try await client.setDefault(id: spec.name)
            }
            // `create` does not boot; the CLI boots separately unless --no-boot.
            if !spec.noBoot {
                _ = try await client.boot(id: spec.name)
            }
        } catch {
            throw mapMachineError(error)
        }
    }

    func setMachineConfig(id: String, config: MachineConfigSpec) async throws {
        do {
            if let kernelPath = config.kernelPath, !kernelPath.isEmpty {
                _ = try MachineConfig.validateKernelPath(kernelPath)
            }
            // Build the new boot config from the runtime default plus the edited values.
            // `with` maps the "kernel" string to a FilePath internally, so we avoid importing
            // SystemPackage here; omitting the key leaves the (default nil) kernel unchanged.
            var kwargs = [
                "cpus": "\(config.cpus)",
                "memory": "\(config.memoryGiB)G",
                "home-mount": config.homeMount,
                "virtualization": config.virtualization ? "true" : "false",
            ]
            if let kernelPath = config.kernelPath, !kernelPath.isEmpty {
                kwargs["kernel"] = kernelPath
            }
            let bootConfig = try MachineConfig.default.with(kwargs)
            try await MachineClient().setConfig(id: id, bootConfig: bootConfig)
        } catch {
            throw mapMachineError(error)
        }
    }

    func bootMachine(id: String) async throws {
        do {
            _ = try await MachineClient().boot(id: id)
        } catch {
            throw mapMachineError(error)
        }
    }

    func stopMachine(id: String) async throws {
        do {
            try await MachineClient().stop(id: id)
        } catch {
            throw mapMachineError(error)
        }
    }

    func deleteMachine(id: String) async throws {
        do {
            try await MachineClient().delete(id: id)
        } catch {
            throw mapMachineError(error)
        }
    }

    func setDefaultMachine(id: String) async throws {
        do {
            try await MachineClient().setDefault(id: id)
        } catch {
            throw mapMachineError(error)
        }
    }

    func machineLogs(id: String) async throws -> [FileHandle] {
        do {
            return try await MachineClient().logs(id: id)
        } catch {
            throw mapMachineError(error)
        }
    }
}

// MARK: - Mapping

/// Translate a client `MachineSnapshot` into the app's `Machine`. `isDefault` is supplied by
/// the caller since the snapshot does not carry it (it comes from the machine API's separate
/// `getDefault()` route).
func mapMachine(_ snapshot: MachineSnapshot, isDefault: Bool) -> Machine {
    Machine(
        id: snapshot.id,
        status: snapshot.status.rawValue,
        isDefault: isDefault,
        cpus: snapshot.bootConfig.cpus,
        memoryBytes: Int(snapshot.bootConfig.memory.toUInt64(unit: .bytes)),
        diskSizeBytes: snapshot.diskSize.map { Int($0) },
        homeMount: snapshot.bootConfig.homeMount.rawValue,
        virtualization: snapshot.bootConfig.virtualization,
        kernelPath: snapshot.bootConfig.kernelPath?.string,
        imageReference: snapshot.configuration.image.reference,
        platform: mapPlatform(snapshot.platform),
        ipAddress: snapshot.ipAddress,
        containerId: snapshot.containerId,
        createdDate: snapshot.createdDate,
        startedDate: snapshot.startedDate,
        initialized: snapshot.initialized,
        userSetup: MachineUserSetup(
            username: snapshot.configuration.userSetup.username,
            uid: Int(snapshot.configuration.userSetup.uid),
            gid: Int(snapshot.configuration.userSetup.gid)
        )
    )
}

// MARK: - Error mapping

/// Map a raw machine-client error to a typed `OrchardError`. The machine API server is a
/// separate on-demand Mach service; when the installed `container` predates machine support
/// the XPC connection fails, which we surface as `.machineApiUnavailable` rather than a raw
/// XPC string. Everything else passes through unchanged for the service's generic alert.
func mapMachineError(_ error: Error) -> Error {
    isMachineServiceUnavailable(error) ? OrchardError.machineApiUnavailable : error
}

/// Best-effort detection that the machine API server could not be reached (as opposed to a
/// per-machine failure). The XPC layer has no typed "service missing" error, so this matches
/// the connection-level phrases it produces. Defensive by design — see the M0 findings note
/// that the absent-daemon case can't be reproduced on a machine-capable install.
func isMachineServiceUnavailable(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("connection invalid")
        || message.contains("connection interrupted")
        || message.contains("couldn’t communicate")
        || message.contains("couldn't communicate")
        || message.contains("machine-apiserver")
        || message.contains("service could not")
        || message.contains("no such xpc")
}
