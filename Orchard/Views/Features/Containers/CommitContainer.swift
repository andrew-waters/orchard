import SwiftUI

/// The container a Commit to Image sheet is for, as a `sheet(item:)` value.
struct CommitSheetTarget: Identifiable {
    let id: String
}

/// Commit a container's filesystem to an image (container 1.6.0+). Asks for the image name,
/// suggesting `<container>:latest`, asks before replacing an image that already exists, and
/// links to the new image when done. Closing the sheet leaves the commit running; the detail
/// header shows that it is still committing. The commit's name, progress and outcome live in
/// `ContainerListService`, so a sheet reopened mid-commit, from any entry point, follows it.
struct CommitContainerView: View {
    let containerId: String

    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    @Environment(\.dismiss) private var dismiss

    @State private var reference: String
    @State private var validationError: String?
    /// The stored image the name would replace, from the last check of the current name.
    @State private var existingImage: String?
    @State private var showReplaceConfirmation = false
    @State private var showRunImage = false

    init(containerId: String) {
        self.containerId = containerId
        _reference = State(initialValue: "\(containerId.lowercased()):latest")
    }

    private var trimmedReference: String {
        reference.trimmingCharacters(in: .whitespaces)
    }

    private var phase: ContainerCommitPhase? {
        containerListService.committingContainers[containerId]?.phase
    }

    /// The image this container was last committed to, while the field still holds the name
    /// that commit was asked for. Editing the name goes back to the form.
    private var committedReference: String? {
        guard phase == nil,
              let outcome = containerListService.lastCommits[containerId],
              outcome.requested == trimmedReference else { return nil }
        return outcome.stored
    }

    /// The replace warning, hidden while committing and once the commit has landed.
    private var replaceWarning: String? {
        phase == nil && committedReference == nil ? existingImage : nil
    }

    private var isRunning: Bool {
        containerListService.containers
            .first { $0.configuration.id == containerId }?
            .status.lowercased() == "running"
    }

    /// What the replace check depends on: the name and the stored images.
    private var replaceCheckKey: String {
        ([trimmedReference] + imageService.images.map(\.reference)).joined(separator: "\n")
    }

    /// The stored image committing to the current name would replace, normalised the way the
    /// commit will normalise it. Nil for a name that isn't valid yet.
    private func checkExistingImage() async -> String? {
        guard InputValidation.isValidImageReference(trimmedReference) else { return nil }
        return await containerListService.existingCommitTarget(
            trimmedReference, among: imageService.images.map(\.reference))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Image Name").font(.headline)
                    TextField("e.g., myapp:latest", text: $reference)
                        .textFieldStyle(.roundedBorder)
                        .disabled(phase != nil)
                        .onChange(of: reference) { _, _ in
                            validationError = nil
                        }
                        .accessibilityIdentifier("commit-image-reference")
                    Text("Lowercase repository name with an optional :tag.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("The image holds the container's filesystem as a single layer, and starts the way the container did: the same command, user, environment, working directory, labels and stop signal. Ports, volumes and the healthcheck aren't carried over. The container's executable becomes the entrypoint, so to run a different program, override the entrypoint, not just the command.")
                    if isRunning {
                        Text("A running container is snapshotted first and keeps running.")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if let existingImage = replaceWarning {
                    HStack(alignment: .top, spacing: 8) {
                        SwiftUI.Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("An image named \(existingImage) already exists. Committing replaces it; containers already created from it keep running.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let validationError {
                    Text(validationError)
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                status
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 480, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Follow a commit already running for this container, or the one that last
            // finished, rather than offering a fresh form over it.
            if let progress = containerListService.committingContainers[containerId] {
                reference = progress.reference
            } else if let outcome = containerListService.lastCommits[containerId] {
                reference = outcome.requested
            }
        }
        .task(id: replaceCheckKey) {
            // The XPC round trip doesn't stop when SwiftUI cancels this task for a newer
            // name, so a late answer for the old name must not overwrite the new one's.
            let found = await checkExistingImage()
            if !Task.isCancelled { existingImage = found }
        }
        .alert("Replace Image?", isPresented: $showReplaceConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Replace", role: .destructive) { commit() }
        } message: {
            Text("\(existingImage ?? trimmedReference) will point at the committed image. The image it replaces stays on disk until you prune images.")
        }
        .sheet(isPresented: $showRunImage) {
            if let committedReference {
                RunContainerView(imageName: committedReference)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Commit to Image").font(.title2).fontWeight(.semibold)
            Spacer()
            Button(phase != nil || committedReference != nil ? "Close" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .help(phase != nil ? "The commit keeps running; the image appears in the Images tab when it's done." : "")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)
    }

    @ViewBuilder
    private var status: some View {
        if let phase {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(phase.rawValue).font(.subheadline).foregroundStyle(.secondary)
            }
        } else if let committedReference {
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Committed \(committedReference)")
                    .font(.subheadline).fontWeight(.medium)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if let committedReference {
                Button("Commit Again") { requestCommit() }
                Button("Run Image") { showRunImage = true }
                // The same destination as orchard://image/<reference>.
                Button("View Image") {
                    NotificationCenter.default.post(name: NSNotification.Name("NavigateToImage"), object: committedReference)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Show the committed image in the Images tab")
            } else {
                Button(replaceWarning == nil ? "Commit" : "Replace Image") { requestCommit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedReference.isEmpty || phase != nil)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("commit-image-start")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
    }

    private func requestCommit() {
        guard InputValidation.isValidImageReference(trimmedReference) else {
            validationError = InputValidation.invalidImageReferenceMessage
            return
        }
        validationError = nil
        // Check again rather than trust the last background check, which may not have
        // finished for the name as typed, so a replace is never committed without asking.
        Task {
            existingImage = await checkExistingImage()
            if existingImage != nil {
                showReplaceConfirmation = true
            } else {
                commit()
            }
        }
    }

    private func commit() {
        let target = trimmedReference
        Task { await containerListService.commitContainer(containerId, to: target) }
    }
}
