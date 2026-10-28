import SwiftUI
import AppKit

/// The Volumes tab's list (#161): every volume, named and anonymous, with its size and
/// whether a container mounts it. Selection lives on `VolumeService`.
struct VolumesListView: View {
    @EnvironmentObject var volumeService: VolumeService
    @Binding var searchText: String
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // The background refresh reads which containers mount volumes only while this
            // tab shows, so read them now, and every size again.
            await volumeService.load(showLoading: false)
            await volumeService.refreshSizes()
        }
        .sheet(isPresented: $volumeService.presentsCreateSheet) {
            AddVolumeView { volume in volumeService.selection = [volume.name] }
        }
        .sheet(isPresented: $volumeService.presentsPruneSheet, onDismiss: {
            Task { await volumeService.load(showLoading: false) }
        }) {
            FreeUpSpaceView(scope: .volumes)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if volumeService.isLoading && volumeService.volumes.isEmpty {
            VStack {
                ProgressView()
                    .padding()
                Text("Loading volumes...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredVolumes.isEmpty {
            emptyStateView
        } else {
            volumesList
        }
    }

    private var emptyStateView: some View {
        VStack {
            SwiftUI.Image(systemName: "cylinder")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text(volumeService.volumes.isEmpty ? "No Volumes" : "No Matching Volumes")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(volumeService.volumes.isEmpty
                 ? "Create a volume, or run a container with one"
                 : volumeService.showOnlyUnused ? "Every volume is mounted, or kept for a compose project" : "Nothing matches the search")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var volumesList: some View {
        List(selection: $volumeService.selection) {
            ForEach(filteredVolumes) { volume in
                let targets = volumeService.selection.contains(volume.name) && volumeService.selection.count > 1
                    ? volumeService.volumes.filter { volumeService.selection.contains($0.name) }
                    : [volume]
                VolumeRowView(
                    volume: volume,
                    size: volumeService.sizes[volume.name],
                    userCount: volumeService.users(of: volume).count,
                    isSelected: volumeService.selection.contains(volume.name)
                )
                .contextMenu {
                    // A menu item shows no tooltip, so a mounted volume says who holds it here.
                    let holders = VolumeUsage.holders(of: targets, in: volumeService.containers)
                    if holders.isEmpty {
                        VolumeDeleteButton(volumes: targets)
                    } else {
                        Button("Can't Delete: In Use by \(ListFormatter.localizedString(byJoining: holders))") {}
                            .disabled(true)
                    }
                }
                .tag(volume.name)
            }
        }
        .listStyle(PlainListStyle())
        .environment(\.defaultMinListRowHeight, ListItemRow.twoLineHeight)
        .animation(.easeInOut(duration: 0.3), value: volumeService.volumes)
        .focused($listFocusedTab, equals: .volumes)
    }

    private var filteredVolumes: [ContainerVolume] {
        volumeService.volumes.filter { volume in
            (searchText.isEmpty || volume.name.localizedCaseInsensitiveContains(searchText))
                && (!volumeService.showOnlyUnused || volumeService.isUnused(volume))
        }
    }
}

private struct VolumeRowView: View {
    let volume: ContainerVolume
    let size: MeasuredSize?
    let userCount: Int
    let isSelected: Bool

    var body: some View {
        ListItemRow(
            icon: TabSelection.volumes.icon,
            iconColor: userCount > 0 ? .green : .secondary,
            primaryText: volume.name,
            secondaryLeftText: details,
            secondaryRightText: usage,
            isSelected: isSelected,
            pluginBadge: VolumeUsage.composeProject(of: volume).map { "compose · \($0)" }
                ?? (volume.isAnonymous ? "anonymous" : nil)
        )
        .help(labelsHelp)
    }

    private var details: String {
        var parts = [VolumeFormat.size(size), volume.format,
                     volume.creationDate.formatted(.relative(presentation: .named))]
        if !volume.labels.isEmpty {
            parts.append("\(volume.labels.count) label\(volume.labels.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    /// A compose volume nothing mounts isn't unused: Prune Volumes keeps it while the project
    /// is down.
    private var usage: String {
        if userCount > 0 { return "\(userCount) container\(userCount == 1 ? "" : "s")" }
        return VolumeUsage.composeProject(of: volume) == nil ? "Unused" : "Kept for compose"
    }

    private var labelsHelp: String {
        volume.labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}

/// Deletes volumes after a confirmation. Disabled while any of them is mounted, with the
/// containers holding them in its tooltip: the runtime refuses to delete a mounted volume.
struct VolumeDeleteButton: View {
    @EnvironmentObject var volumeService: VolumeService
    let volumes: [ContainerVolume]
    var title: String? = nil
    var prominent = false

    private var blocker: String? {
        VolumeUsage.deleteBlocker(volumes, containers: volumeService.containers)
    }

    var body: some View {
        let button = Button(title ?? (volumes.count > 1 ? "Delete \(volumes.count) Volumes..." : "Delete Volume..."), role: .destructive) {
            confirmDeletion()
        }
        .disabled(volumes.isEmpty || blocker != nil)
        .help(blocker ?? "Delete \(volumes.count > 1 ? "these volumes" : "this volume") and everything in \(volumes.count > 1 ? "them" : "it")")
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button
        }
    }

    private func confirmDeletion() {
        let alert = NSAlert()
        alert.messageText = volumes.count > 1 ? "Delete \(volumes.count) Volumes?" : "Delete \(volumes[0].name)?"
        let names = volumes.map(\.name).joined(separator: ", ")
        alert.informativeText = volumes.count > 1
            ? "This deletes \(names). What's in them can't be got back."
            : "What's in the volume can't be got back."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let names = volumes.map(\.name)
            Task { await volumeService.delete(names) }
        }
    }
}

/// How the Volumes views write a size that may still be being read.
enum VolumeFormat {
    static func size(_ size: MeasuredSize?) -> String {
        switch size {
        case .known(let bytes): return ByteFormat.string(bytes)
        case .failed: return "Size unknown"
        case .measuring, nil: return "Measuring..."
        }
    }
}
