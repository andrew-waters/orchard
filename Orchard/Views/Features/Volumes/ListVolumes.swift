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
        .task { await volumeService.refreshSizes() }
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
                 : volumeService.showOnlyUnused ? "Every volume is mounted by a container" : "Nothing matches the search")
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
                    VolumeDeleteButton(volumes: targets)
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
                && (!volumeService.showOnlyUnused || volumeService.users(of: volume).isEmpty)
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
            secondaryLeftText: "\(VolumeFormat.size(size)) · \(volume.format)",
            secondaryRightText: userCount == 0 ? "Unused" : "\(userCount) container\(userCount == 1 ? "" : "s")",
            isSelected: isSelected,
            pluginBadge: volume.isAnonymous ? "anonymous" : nil
        )
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
