import Foundation
import ComposePlanner

// Freeing disk space (#159): what counts as unused, what the user chose, and carrying it out.
// The rules are pure functions over a fresh read of the runtime, so the preview and the purge
// decide the same way, and the purge decides again just before it removes anything.

/// One thing a purge can remove.
enum DiskPurgeItem: Hashable, Sendable {
    case image(reference: String)
    case container(id: String)
    case volume(name: String)

    var name: String {
        switch self {
        case .image(let reference): return reference
        case .container(let id): return id
        case .volume(let name): return name
        }
    }
}

/// What is on disk, read in one go.
struct DiskPurgeInventory: Equatable, Sendable {
    /// Every container, machine backing containers included.
    var containers: [Container]
    var images: [ContainerImage]
    var volumes: [ContainerVolume]
    /// Images the runtime needs although no container lists them.
    var systemImageReferences: Set<String>
}

/// What counts as unused in an inventory.
struct DiskPurgeCandidates: Equatable, Sendable {
    var containers: [Container] = []
    var images: [ContainerImage] = []
    var volumes: [ContainerVolume] = []
}

/// The sections the user has turned on, and the items whose tick differs from its default.
/// Kept as differences so an item that becomes a candidate later (an image freed by ticking
/// the only container using it) starts with its default.
struct DiskPurgeSelection: Equatable {
    var includeImages = true
    var includeContainers = false
    var includeVolumes = false
    private(set) var flipped: Set<DiskPurgeItem> = []

    func isTicked(_ item: DiskPurgeItem, byDefault: Bool) -> Bool {
        flipped.contains(item) != byDefault
    }

    mutating func setTicked(_ ticked: Bool, _ item: DiskPurgeItem, byDefault: Bool) {
        if ticked == byDefault {
            flipped.remove(item)
        } else {
            flipped.insert(item)
        }
    }
}

/// What to remove, by name, in the order a purge works through it.
struct DiskPurgePlan: Equatable, Sendable {
    var containerIDs: [String] = []
    var imageReferences: [String] = []
    var volumeNames: [String] = []
    /// Clear out image data nothing refers to, which deleting an image leaves behind.
    var cleansImageStore = false

    var count: Int { containerIDs.count + imageReferences.count + volumeNames.count }
}

/// The candidates with the ticked containers counted as gone, and the plan for the ticked items.
struct DiskPurgePreview: Equatable {
    var candidates: DiskPurgeCandidates
    var plan: DiskPurgePlan
    /// Images and volumes that are candidates only because the ticked containers go.
    var freedByContainers: Set<DiskPurgeItem>
}

struct DiskPurgeResult: Equatable, Sendable {
    struct Failure: Equatable, Sendable {
        /// Nil for a failure that isn't one item's, such as cleaning up image data.
        let item: DiskPurgeItem?
        let message: String
    }

    var removed: [DiskPurgeItem] = []
    /// Chosen in the preview but in use by the time the purge ran, so left alone.
    var skipped: [DiskPurgeItem] = []
    var failures: [Failure] = []
    var freedBytes: UInt64 = 0
}

enum DiskPurge {
    /// A stopped container that nothing else manages. Machines, cluster nodes and the builder
    /// carry a plugin or role label; compose services and sandboxes belong to their own views.
    static func isRemovable(_ container: Container) -> Bool {
        container.status == "stopped"
            && container.owningPlugin == nil
            && container.pluginRole == nil
            && container.composeProjectName == nil
            && !container.isSandbox
    }

    /// Whether a container mounts the volume: by name, or by sharing a path inside the
    /// volume's storage, as a container an Orchard before #160 recreated does.
    static func volume(_ volume: ContainerVolume, isMountedBy container: Container) -> Bool {
        container.configuration.mounts.contains { mount in
            if mount.type.volume?.name == volume.name { return true }
            guard let directory = volume.storageDirectory, !mount.source.isEmpty else { return false }
            let source = (mount.source as NSString).standardizingPath
            let storage = (directory as NSString).standardizingPath
            return source == storage || source.hasPrefix(storage + "/")
        }
    }

    /// A volume a compose project made. Kept while the project is down, which is the point of
    /// it; taking the project down is where its volumes are removed.
    static func isComposeVolume(_ volume: ContainerVolume) -> Bool {
        !(volume.labels[ProjectIdentity.projectLabel] ?? "").isEmpty
    }

    /// Images start ticked; containers and named volumes start unticked, since they hold data
    /// that can't be got back. Anonymous volumes are throwaway, so they start ticked.
    static func isTickedByDefault(_ item: DiskPurgeItem, in inventory: DiskPurgeInventory) -> Bool {
        switch item {
        case .image: return true
        case .container: return false
        case .volume(let name): return inventory.volumes.first { $0.name == name }?.isAnonymous ?? false
        }
    }

    /// What is unused, counting the containers in `removing` as gone where they can be removed.
    /// An image is in use when any other container, running or not, is made from it, or the
    /// runtime needs it. A volume is in use when any other container mounts it.
    static func candidates(
        in inventory: DiskPurgeInventory,
        removingContainers removing: Set<String> = []
    ) -> DiskPurgeCandidates {
        let removable = inventory.containers.filter(isRemovable)
        let removed = Set(removable.map(\.configuration.id)).intersection(removing)
        let remaining = inventory.containers.filter { !removed.contains($0.configuration.id) }
        let imagesInUse = Set(remaining.map(\.configuration.image.reference))
            .union(inventory.systemImageReferences)
        return DiskPurgeCandidates(
            containers: removable,
            images: inventory.images.filter { !imagesInUse.contains($0.reference) },
            volumes: inventory.volumes.filter { candidate in
                !isComposeVolume(candidate) && !remaining.contains { volume(candidate, isMountedBy: $0) }
            }
        )
    }

    static func preview(_ inventory: DiskPurgeInventory, selection: DiskPurgeSelection) -> DiskPurgePreview {
        func ticked(_ item: DiskPurgeItem) -> Bool {
            selection.isTicked(item, byDefault: isTickedByDefault(item, in: inventory))
        }
        let base = candidates(in: inventory)
        let removing = selection.includeContainers
            ? base.containers.map(\.configuration.id).filter { ticked(.container(id: $0)) }
            : []
        let after = candidates(in: inventory, removingContainers: Set(removing))

        var plan = DiskPurgePlan(containerIDs: removing, cleansImageStore: selection.includeImages)
        if selection.includeImages {
            plan.imageReferences = after.images.map(\.reference).filter { ticked(.image(reference: $0)) }
        }
        if selection.includeVolumes {
            plan.volumeNames = after.volumes.map(\.name).filter { ticked(.volume(name: $0)) }
        }

        let before = Set(base.images.map { DiskPurgeItem.image(reference: $0.reference) })
            .union(base.volumes.map { .volume(name: $0.name) })
        let freed = Set(after.images.map { DiskPurgeItem.image(reference: $0.reference) })
            .union(after.volumes.map { .volume(name: $0.name) })
            .subtracting(before)
        return DiskPurgePreview(candidates: after, plan: plan, freedByContainers: freed)
    }

    static func readInventory(_ backend: ContainerBackend) async throws -> DiskPurgeInventory {
        async let containers = backend.listAllContainers()
        async let images = backend.listImages()
        async let volumes = backend.listVolumes()
        async let systemImages = backend.systemImageReferences()
        return DiskPurgeInventory(
            containers: try await containers,
            images: try await images,
            volumes: try await volumes,
            systemImageReferences: Set(try await systemImages)
        )
    }

    /// Carry out a plan made from an earlier preview. Reads the runtime again first and leaves
    /// alone anything that has come into use since; then decides images and volumes only once
    /// the containers have gone, so one that failed to go keeps what it uses.
    static func purge(_ plan: DiskPurgePlan, backend: ContainerBackend) async throws -> DiskPurgeResult {
        var result = DiskPurgeResult()
        let inventory = try await readInventory(backend)

        let removable = Set(candidates(in: inventory).containers.map(\.configuration.id))
        var removedContainers = Set<String>()
        for id in plan.containerIDs {
            let item = DiskPurgeItem.container(id: id)
            guard removable.contains(id) else {
                result.skipped.append(item)
                continue
            }
            do {
                let size = (try? await backend.containerDiskUsage(id: id)) ?? 0
                try await backend.deleteContainer(id: id, force: false)
                removedContainers.insert(id)
                result.removed.append(item)
                result.freedBytes += size
            } catch {
                result.failures.append(.init(item: item, message: error.localizedDescription))
            }
        }

        let unused = candidates(in: inventory, removingContainers: removedContainers)

        let unusedImages = Set(unused.images.map(\.reference))
        for reference in plan.imageReferences {
            let item = DiskPurgeItem.image(reference: reference)
            guard unusedImages.contains(reference) else {
                result.skipped.append(item)
                continue
            }
            do {
                try await backend.deleteImage(reference: reference)
                result.removed.append(item)
            } catch {
                result.failures.append(.init(item: item, message: error.localizedDescription))
            }
        }
        if plan.cleansImageStore {
            do {
                result.freedBytes += try await backend.cleanUpOrphanedBlobs()
            } catch {
                result.failures.append(.init(item: nil, message: "Cleaning up image data: \(error.localizedDescription)"))
            }
        }

        let unusedVolumes = Set(unused.volumes.map(\.name))
        for name in plan.volumeNames {
            let item = DiskPurgeItem.volume(name: name)
            guard unusedVolumes.contains(name) else {
                result.skipped.append(item)
                continue
            }
            do {
                let size = (try? await backend.volumeDiskUsage(name: name)) ?? 0
                try await backend.deleteVolume(name: name)
                result.removed.append(item)
                result.freedBytes += size
            } catch {
                result.failures.append(.init(item: item, message: error.localizedDescription))
            }
        }
        return result
    }
}

/// Loads what a purge could remove, with sizes, and runs the purge the user confirms.
@MainActor
final class DiskPurgeService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case purging
        case finished(DiskPurgeResult)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var inventory: DiskPurgeInventory?
    /// Disk usage of candidate containers and volumes, filled in as each arrives. Missing
    /// means not known yet, or the runtime couldn't say.
    @Published private(set) var containerSizes: [String: UInt64] = [:]
    @Published private(set) var volumeSizes: [String: UInt64] = [:]

    private let backend: ContainerBackend

    /// Refresh disk usage and the lists a purge changes. Set by the owner.
    var onPurged: () async -> Void = {}

    init(backend: ContainerBackend) {
        self.backend = backend
    }

    func load() async {
        phase = .loading
        containerSizes = [:]
        volumeSizes = [:]
        do {
            let inventory = try await DiskPurge.readInventory(backend)
            self.inventory = inventory
            phase = .ready
            // Every volume, not only the unused ones: ticking a container can free its volumes.
            await loadSizes(
                containers: DiskPurge.candidates(in: inventory).containers,
                volumes: inventory.volumes
            )
        } catch {
            inventory = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func purge(_ plan: DiskPurgePlan) async {
        phase = .purging
        do {
            let result = try await DiskPurge.purge(plan, backend: backend)
            phase = .finished(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
        await onPurged()
    }

    private enum Size {
        case container(String, UInt64)
        case volume(String, UInt64)
    }

    private func loadSizes(containers: [Container], volumes: [ContainerVolume]) async {
        let backend = backend
        await withTaskGroup(of: Size?.self) { group in
            for container in containers {
                let id = container.configuration.id
                group.addTask { (try? await backend.containerDiskUsage(id: id)).map { .container(id, $0) } }
            }
            for volume in volumes {
                let name = volume.name
                group.addTask { (try? await backend.volumeDiskUsage(name: name)).map { .volume(name, $0) } }
            }
            for await size in group {
                switch size {
                case .container(let id, let bytes): containerSizes[id] = bytes
                case .volume(let name, let bytes): volumeSizes[name] = bytes
                case nil: break
                }
            }
        }
    }
}
