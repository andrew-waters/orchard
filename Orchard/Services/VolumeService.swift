import Foundation
import ComposePlanner

/// Which containers hold a volume (#161). "In use" is `DiskPurge`'s rule, so the Volumes tab
/// and Free Up Space agree on it.
enum VolumeUsage {
    /// The containers that mount `volume`, by name or by a path inside its storage.
    static func users(of volume: ContainerVolume, in containers: [Container]) -> [Container] {
        containers.filter { DiskPurge.volume(volume, isMountedBy: $0) }
    }

    /// Whether Prune Volumes would offer the volume: nothing mounts it, and it isn't a compose
    /// project's, which is kept while the project is down.
    static func isUnused(_ volume: ContainerVolume, in containers: [Container]) -> Bool {
        !DiskPurge.isComposeVolume(volume) && users(of: volume, in: containers).isEmpty
    }

    /// The compose project a volume belongs to, if any.
    static func composeProject(of volume: ContainerVolume) -> String? {
        volume.labels[ProjectIdentity.projectLabel].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The containers mounting any of `volumes`, by id, each once.
    static func holders(of volumes: [ContainerVolume], in containers: [Container]) -> [String] {
        var seen = Set<String>()
        return volumes.flatMap { users(of: $0, in: containers).map(\.configuration.id) }
            .filter { seen.insert($0).inserted }
    }

    /// Why `volumes` can't be deleted: each one a container mounts, and what mounts it. Nil
    /// when none is mounted.
    static func deleteBlocker(_ volumes: [ContainerVolume], containers: [Container]) -> String? {
        let held = volumes.compactMap { volume -> String? in
            let users = users(of: volume, in: containers).map(\.configuration.id)
            guard !users.isEmpty else { return nil }
            return "\(volume.name) is mounted by \(ListFormatter.localizedString(byJoining: users))"
        }
        guard !held.isEmpty else { return nil }
        return "Remove the containers using it first: \(held.joined(separator: "; "))."
    }
}

/// Owns the Volumes tab's state: the volumes, the containers that might mount them, and each
/// volume's size on disk.
@MainActor
final class VolumeService: ObservableObject {
    @Published private(set) var volumes: [ContainerVolume] = []
    /// Every container, machines included, so a volume a machine mounts counts as in use.
    @Published private(set) var containers: [Container] = []
    /// Disk usage by volume name. Missing means not read yet.
    @Published private(set) var sizes: [String: MeasuredSize] = [:]
    @Published private(set) var isLoading = false
    /// The rows selected in the Volumes tab, by name. Kept here, as Compose keeps its selected
    /// project, so links and Cmd+K can select a volume without threading more bindings.
    @Published var selection: Set<String> = []
    @Published var showOnlyUnused = false
    @Published var presentsCreateSheet = false
    @Published var presentsPruneSheet = false

    private let backend: ContainerBackend
    private let alertCenter: AlertCenter

    init(backend: ContainerBackend, alertCenter: AlertCenter) {
        self.backend = backend
        self.alertCenter = alertCenter
    }

    var selectedVolume: String? { selection.count == 1 ? selection.first : nil }

    func users(of volume: ContainerVolume) -> [Container] {
        VolumeUsage.users(of: volume, in: containers)
    }

    func isUnused(_ volume: ContainerVolume) -> Bool {
        VolumeUsage.isUnused(volume, in: containers)
    }

    /// Volumes listed, sorted by name. Measures the size of any volume not measured yet;
    /// `refreshSizes` reads them all again. `readsContainers` also reads which containers
    /// mount them, which only the Volumes tab and a delete need, so a background refresh
    /// elsewhere, or a form listing volumes to pick from, leaves it off.
    func load(showLoading: Bool = true, readsContainers: Bool = true) async {
        if showLoading {
            isLoading = true
        }
        do {
            async let listedVolumes = backend.listVolumes()
            async let listedContainers: [Container]? = readsContainers ? backend.listAllContainers() : nil
            let volumes = try await listedVolumes.sorted { $0.name < $1.name }
            if volumes != self.volumes { self.volumes = volumes }
            if let containers = try await listedContainers, containers != self.containers {
                self.containers = containers
            }
            let names = Set(volumes.map(\.name))
            if !selection.isSubset(of: names) { selection.formIntersection(names) }
            sizes = sizes.filter { names.contains($0.key) }
            isLoading = false
            await measure(volumes.filter { sizes[$0.name] == nil })
        } catch {
            if showLoading {
                alertCenter.error("Failed to load volumes: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    /// Read every volume's size again. Sizes grow as volumes fill, but each is a call to the
    /// runtime, so the background refresh leaves known sizes alone.
    func refreshSizes() async {
        await measure(volumes)
    }

    /// Create a volume and reload. Throws, so the sheet can show why: the app's alert can't
    /// appear over a sheet.
    func create(name: String, size: String?, labels: [String: String]) async throws -> ContainerVolume {
        let volume = try await backend.createVolume(name: name, size: size, labels: labels)
        await load(showLoading: false)
        return volume
    }

    /// Delete each volume, then reload. A volume a container started mounting since the
    /// Delete button was enabled fails in the runtime; the error names what holds it.
    func delete(_ names: [String]) async {
        var failed: [(name: String, error: Error)] = []
        for name in names {
            do {
                try await backend.deleteVolume(name: name)
            } catch {
                failed.append((name, error))
            }
        }
        await load(showLoading: false)
        guard !failed.isEmpty else { return }
        let messages = failed.map { name, error in
            if let volume = volumes.first(where: { $0.name == name }),
               let blocker = VolumeUsage.deleteBlocker([volume], containers: containers) {
                return blocker
            }
            return "\(name): \(error.localizedDescription)"
        }
        alertCenter.error("Failed to delete \(failed.count == 1 ? "a volume" : "\(failed.count) volumes"). \(messages.joined(separator: " "))")
    }

    private func measure(_ volumes: [ContainerVolume]) async {
        let backend = backend
        await withTaskGroup(of: (String, MeasuredSize).self) { group in
            for volume in volumes {
                let name = volume.name
                group.addTask {
                    let bytes = try? await backend.volumeDiskUsage(name: name)
                    return (name, bytes.map { .known(Int64(clamping: $0)) } ?? .failed)
                }
            }
            for await (name, size) in group {
                sizes[name] = size
            }
        }
    }
}
