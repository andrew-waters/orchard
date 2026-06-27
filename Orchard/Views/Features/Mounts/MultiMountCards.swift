import AppKit
import SwiftUI

struct MultiMountCardsView: View {
    @EnvironmentObject var containerService: ContainerService
    let mountIds: Set<String>
    @Binding var selectedMountsBinding: Set<String>

    @State private var showDeleteConfirmation = false

    private var selectedMountsList: [ContainerMount] {
        containerService.allMounts
            .filter { mountIds.contains($0.id) }
            .sorted { $0.mount.destination < $1.mount.destination }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(selectedMountsList, id: \.id) { mount in
                        MountSummaryCard(mount: mount) {
                            selectedMountsBinding = [mount.id]
                        }
                        .environmentObject(containerService)
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            "Remove selected mounts?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let list = selectedMountsList.map { "• \($0.mount.source) -> \($0.mount.destination)" }.joined(separator: "\n")
            Text("The following \(selectedMountsList.count) mount(s) will be removed from all associated containers (which will be recreated):\n\n\(list)")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(selectedMountsList.count) mounts selected")
                .font(.headline)

            Spacer()

            Button("Remove selected mounts") {
                showDeleteConfirmation = true
            }
            .foregroundColor(.red)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func performDelete() {
        Task {
            await containerService.deleteMounts(selectedMountsList)
        }
    }
}

private struct MountSummaryCard: View {
    @EnvironmentObject var containerService: ContainerService
    let mount: ContainerMount
    let onOpen: () -> Void

    private var mountName: String {
        URL(fileURLWithPath: mount.mount.source).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SwiftUI.Image(systemName: "externaldrive")
                    .foregroundColor(.secondary)

                Text(mountName)
                    .font(.system(.headline, design: .default))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Remove") {
                    let alert = NSAlert()
                    alert.messageText = "Remove Mount"
                    alert.informativeText = "Are you sure you want to remove this mount? The associated containers will be deleted and recreated without it."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Remove")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        Task { await containerService.deleteMounts([mount]) }
                    }
                }
                .foregroundColor(.red)

                Button("Open") {
                    onOpen()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "Source Path", value: mount.mount.source)
                InfoRow(label: "Destination Path", value: mount.mount.destination)
                InfoRow(label: "Type", value: mount.mountType)
                InfoRow(label: "Options", value: mount.optionsString)
                InfoRow(label: "Containers", value: mount.containerIds.joined(separator: ", "))
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
