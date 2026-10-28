import SwiftUI

/// The Volumes tab's detail column: one volume, the cards for several, or a prompt.
struct VolumeDetailContent: View {
    @EnvironmentObject var volumeService: VolumeService
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    var body: some View {
        if volumeService.selection.count > 1 {
            MultiVolumeCardsView()
        } else if let name = volumeService.selectedVolume,
                  let volume = volumeService.volumes.first(where: { $0.name == name }) {
            VolumeDetailView(volume: volume, selectedTab: $selectedTab, selectedContainer: $selectedContainer)
        } else {
            Text(volumeService.selection.isEmpty ? "Select a volume" : "Volume not found")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct VolumeDetailView: View {
    @EnvironmentObject var volumeService: VolumeService
    let volume: ContainerVolume
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    @State private var showRunSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overviewSection
                    labelsSection
                    usersSection
                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showRunSheet) {
            RunContainerView(volume: volume.name)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if volume.isAnonymous {
                    Text("Anonymous volume, made by the runtime for a mount with no name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Button("Run Container...") { showRunSheet = true }
                    .help("Run a container with this volume mounted")
                VolumeDeleteButton(volumes: [volume], title: "Delete...", prominent: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                CopyableInfoRow(label: "Name", value: volume.name)
                InfoRow(label: "Size on Disk", value: VolumeFormat.size(volumeService.sizes[volume.name]))
                if let capacity = volume.capacityBytes {
                    InfoRow(label: "Capacity", value: ByteFormat.string(Int64(clamping: capacity)))
                }
                InfoRow(label: "Format", value: volume.format)
                InfoRow(label: "Created", value: volume.creationDate.formatted(date: .abbreviated, time: .shortened))
                if !volume.source.isEmpty {
                    CopyableInfoRow(label: "Disk Image", value: volume.source)
                }
            }
        }
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Labels")
                .font(.headline)

            if volume.labels.isEmpty {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(volume.labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        CopyableInfoRow(label: key, value: value)
                    }
                }
            }
        }
    }

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Containers using this volume")
                .font(.headline)

            ContainerTable(
                containers: volumeService.users(of: volume),
                selectedTab: $selectedTab,
                selectedContainer: $selectedContainer,
                emptyStateMessage: "No container mounts this volume"
            )
        }
    }
}

/// Several volumes selected: a card each, and one Delete for them all.
struct MultiVolumeCardsView: View {
    @EnvironmentObject var volumeService: VolumeService

    private var selectedVolumes: [ContainerVolume] {
        volumeService.volumes.filter { volumeService.selection.contains($0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("\(selectedVolumes.count) volumes selected")
                    .font(.headline)
                Spacer()
                VolumeDeleteButton(volumes: selectedVolumes)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(selectedVolumes) { volume in
                        card(volume)
                    }
                }
                .padding(16)
            }
        }
    }

    private func card(_ volume: ContainerVolume) -> some View {
        let users = volumeService.users(of: volume)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SwiftUI.Image(systemName: TabSelection.volumes.icon)
                    .foregroundColor(users.isEmpty ? .secondary : .green)
                Text(volume.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open") { volumeService.selection = [volume.name] }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "Size on Disk", value: VolumeFormat.size(volumeService.sizes[volume.name]))
                InfoRow(label: "Kind", value: volume.isAnonymous ? "Anonymous" : "Named")
                InfoRow(label: "Mounted By", value: users.isEmpty ? "None" : users.map(\.configuration.id).joined(separator: ", "))
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}
