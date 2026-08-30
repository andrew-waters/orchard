import SwiftUI

/// The Builds tab's detail column: one build's status and full log, live while
/// the build runs and reviewable after (including records restored from
/// previous launches).
struct BuildDetailView: View {
    @EnvironmentObject var buildService: ImageBuildService
    @EnvironmentObject var imageService: ImageService
    @EnvironmentObject var containerListService: ContainerListService
    @State private var showRunContainer = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    let buildID: UUID?
    @Binding var selectedTab: TabSelection
    @Binding var selectedContainer: String?

    private var build: ImageBuild? {
        buildID.flatMap { buildService.build(id: $0) }
    }

    /// The built image's reference as the image list knows it. A build tag like
    /// "myapp:latest" may be stored verbatim or canonicalized, and a bare
    /// repository gets :latest - try the variants.
    private var builtImageReference: String? {
        guard let build else { return nil }
        var candidates = [build.tag, canonicalImageReference(build.tag)]
        if !(build.tag.split(separator: "/").last ?? "").contains(":") {
            candidates += candidates.map { "\($0):latest" }
        }
        return imageService.images.first { candidates.contains($0.reference) }?.reference
    }

    private var containersUsingImage: [Container] {
        guard let reference = builtImageReference else { return [] }
        return containerListService.containers.filter {
            $0.configuration.image.reference == reference
        }
    }

    var body: some View {
        if let build {
            VStack(spacing: 0) {
                header(for: build)

                BuildStatusLine(build: build)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if builtImageReference != nil {
                    containersSection
                }

                if build.outputLines.isEmpty {
                    Text("No output yet")
                        .foregroundColor(Color(white: 0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.85))
                } else {
                    LogConsoleView(lines: build.outputLines, filterText: "")
                        .background(Color.black.opacity(0.85))
                }
            }
        } else {
            Text("Select a build")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for build: ImageBuild) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(build.tag)
                    .font(.title2).fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(build.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(BuildPhaseStyle.durationText(build.duration))
                    Text("·")
                    Text(build.request.arch == "amd64" ? "linux/amd64" : "linux/arm64")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                Text(build.request.dockerfile)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(build.request.dockerfile)
            }

            Spacer()

            if build.phase == .building {
                Button("Cancel Build") { buildService.cancel(build.id) }
                    .buttonStyle(BorderedButtonStyle())
            } else {
                if let reference = builtImageReference {
                    Button("Launch image") { showRunContainer = true }
                        .buttonStyle(BorderedButtonStyle())
                        .sheet(isPresented: $showRunContainer) {
                            RunContainerView(imageName: reference)
                        }
                }

                // Deleting removes the record and, when it still exists, the
                // built image - blocked while containers use it. Red prominent
                // when actionable, plain bordered when disabled, matching the
                // image detail's Delete.
                if containersUsingImage.isEmpty {
                    Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .tint(.red)
                        .disabled(isDeleting)
                        .help("Delete this build record\(builtImageReference != nil ? " and the built image" : "")")
                } else {
                    Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                        .buttonStyle(BorderedButtonStyle())
                        .disabled(true)
                        .help("Remove the containers using this image first")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .alert("Delete Build?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteBuildAndImage(build) }
        } message: {
            if let reference = builtImageReference {
                Text("This deletes the build record and the image '\(reference)'. This action cannot be undone.")
            } else {
                Text("This deletes the build record. The image no longer exists (or was never produced), so only the record is removed.")
            }
        }
    }

    private func deleteBuildAndImage(_ build: ImageBuild) {
        isDeleting = true
        let reference = builtImageReference
        let id = build.id
        Task { @MainActor in
            defer { isDeleting = false }
            if let reference {
                await imageService.delete(reference)
                // delete() alerts on failure without reporting it; the image
                // still being listed is the tell. Keep the record in that case.
                guard !imageService.images.contains(where: { $0.reference == reference }) else { return }
            }
            buildService.remove(id)
        }
    }

    /// Containers created from the image this build produced - the same table
    /// the image detail shows, with clickable container/IP/hostname cells.
    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Used By Containers")
                .font(.headline)
                .foregroundColor(.primary)

            ContainerTable(
                containers: containersUsingImage,
                selectedTab: $selectedTab,
                selectedContainer: $selectedContainer,
                emptyStateMessage: "No containers are currently using this image"
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
