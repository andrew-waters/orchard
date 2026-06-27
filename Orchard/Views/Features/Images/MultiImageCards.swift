import AppKit
import SwiftUI

struct MultiImageCardsView: View {
    @EnvironmentObject var containerService: ContainerService
    let imageIds: Set<String>
    @Binding var selectedImagesBinding: Set<String>

    @State private var showDeleteConfirmation = false

    private var selectedImagesList: [ContainerImage] {
        containerService.images
            .filter { imageIds.contains($0.reference) }
            .sorted { $0.reference < $1.reference }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(selectedImagesList, id: \.reference) { image in
                        ImageSummaryCard(image: image) {
                            selectedImagesBinding = [image.reference]
                        }
                        .environmentObject(containerService)
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            "Remove selected images?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let list = selectedImagesList.map { "• \($0.reference)" }.joined(separator: "\n")
            Text("The following \(selectedImagesList.count) image(s) will be removed:\n\n\(list)\n\nThis action cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(selectedImagesList.count) images selected")
                .font(.headline)

            Spacer()

            Button("Remove selected images") {
                showDeleteConfirmation = true
            }
            .foregroundColor(.red)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func performDelete() {
        let targets = selectedImagesList.map { $0.reference }
        Task {
            await containerService.deleteImages(targets)
        }
    }
}

private struct ImageSummaryCard: View {
    @EnvironmentObject var containerService: ContainerService
    let image: ContainerImage
    let onOpen: () -> Void

    private var sizeText: String {
        ByteCountFormatter().string(fromByteCount: Int64(image.descriptor.size))
    }

    private var inUse: Bool {
        containerService.containers.contains { container in
            container.configuration.image.reference == image.reference
        }
    }

    private func imageName(from reference: String) -> String {
        let components = reference.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent.split(separator: ":").first ?? lastComponent)
        }
        return reference
    }

    private func imageTag(from reference: String) -> String {
        if let tagComponent = reference.split(separator: ":").last,
           tagComponent != reference.split(separator: "/").last {
            return String(tagComponent)
        }
        return "latest"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(inUse ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)

                Text(imageName(from: image.reference))
                    .font(.system(.headline, design: .default))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(imageTag(from: image.reference))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundColor(.secondary)

                Spacer()

                Button("Remove") {
                    let ref = image.reference
                    Task { await containerService.deleteImages([ref]) }
                }
                .foregroundColor(.red)

                Button("Open") {
                    onOpen()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "Full Reference", value: image.reference)
                InfoRow(label: "Size", value: sizeText)
                InfoRow(label: "Digest", value: image.descriptor.digest)
                InfoRow(label: "Status", value: inUse ? "In use" : "Not in use")
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
