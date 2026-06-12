import SwiftUI
import AppKit

struct RunContainerView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    @Environment(\.dismiss) var dismiss

    let imageName: String
    let allowsImageSelection: Bool
    @State private var config: ContainerRunConfig
    @State private var isRunning = false
    @State private var nameValidationError: String?

    init(imageName: String) {
        self.imageName = imageName
        self.allowsImageSelection = false

        _config = State(initialValue: ContainerRunConfig(
            name: RunContainerView.derivedName(from: imageName),
            image: imageName
        ))
    }

    /// Picker mode: no preselected image; user picks/filters from local images
    /// or pastes any reference.
    init() {
        self.imageName = ""
        self.allowsImageSelection = true

        _config = State(initialValue: ContainerRunConfig(name: "", image: ""))
    }

    private static func derivedName(from imageRef: String) -> String {
        let trimmed = imageRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "container" }

        var s = trimmed
        if let at = s.firstIndex(of: "@") { s = String(s[..<at]) }
        if let slash = s.lastIndex(of: "/") {
            s = String(s[s.index(after: slash)...])
        }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }

        return s.isEmpty ? "container" : s
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if allowsImageSelection {
                imagePickerSection
                Divider()
            }
            ContainerConfigForm(config: $config, nameValidationError: $nameValidationError, mode: .run)
            Divider()
            footerView
        }
        .frame(width: 700, height: 600)
        .task {
            if allowsImageSelection && imageService.images.isEmpty {
                await imageService.load(showLoading: false)
            }
        }
    }

    private var headerView: some View {
        HStack {
            SwiftUI.Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Run Container")
                    .font(.headline)
                    .fontWeight(.semibold)

                if !allowsImageSelection {
                    Text(imageName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                SwiftUI.Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var footerView: some View {
        HStack {
            if isRunning {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Starting container...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Run Container") {
                runContainer()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(config.name.isEmpty || config.image.isEmpty || isRunning || nameValidationError != nil)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var filteredImages: [ContainerImage] {
        guard !config.image.isEmpty else { return imageService.images }
        return imageService.images.filter {
            $0.reference.localizedCaseInsensitiveContains(config.image)
        }
    }

    private func applyImageSelection(_ reference: String) {
        config.image = reference
        if config.name.isEmpty {
            config.name = RunContainerView.derivedName(from: reference)
            validateContainerName()
        }
    }

    private var imagePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 6) {
                TextField("Filter local images or paste reference", text: $config.image)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: config.image) { _, newValue in
                        if config.name.isEmpty && !newValue.isEmpty {
                            config.name = RunContainerView.derivedName(from: newValue)
                            validateContainerName()
                        }
                    }

                Menu {
                    if imageService.images.isEmpty {
                        Text("No local images")
                    } else if filteredImages.isEmpty {
                        Text("No matches")
                    } else {
                        ForEach(filteredImages, id: \.reference) { image in
                            Button(image.reference) {
                                applyImageSelection(image.reference)
                            }
                        }
                    }
                } label: {
                    SwiftUI.Image(systemName: "chevron.down.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
                .help("Browse local images")
            }

            if !config.image.isEmpty {
                if imageService.images.contains(where: { $0.reference == config.image }) {
                    Label("Local image available", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Will be pulled if not present", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func validateContainerName() {
        nameValidationError = ContainerConfigForm.validationError(
            for: config.name, existing: containerListService.containers
        )
    }

    private func runContainer() {
        nameValidationError = ContainerConfigForm.validationError(
            for: config.name, existing: containerListService.containers
        )
        let imageReference = canonicalImageReference(config.image)
        guard nameValidationError == nil, !imageReference.isEmpty else { return }

        isRunning = true
        Task {
            var runConfig = config
            runConfig.image = imageReference
            await containerListService.runContainer(config: runConfig)
            await MainActor.run {
                isRunning = false
                dismiss()
            }
        }
    }
}

#Preview {
    RunContainerView(imageName: "docker.io/library/nginx:latest")
        .injectServices(AppServices())
}
