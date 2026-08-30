import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Build an image from a Dockerfile via `container build`. The Dockerfile is
/// picked with a file panel (so non-default names like `Dockerfile.dev` are
/// discoverable), the context defaults to the Dockerfile's folder, and the
/// build log streams into the shared ANSI console. Each build registers with
/// the service's builds list, so closing the sheet leaves it running and the
/// Builds menu can reopen its log.
struct BuildImageView: View {
    @EnvironmentObject var buildService: ImageBuildService
    @Environment(\.dismiss) private var dismiss

    @State private var dockerfile: String = ""
    @State private var contextDir: String = ""
    @State private var tag: String = ""
    @State private var arch: String = hostContainerArchitecture
    @State private var noCache: Bool = false
    @State private var validationError: String?
    /// The build this sheet started; its record drives the status/console.
    @State private var currentBuildID: UUID?

    private var currentBuild: ImageBuild? {
        currentBuildID.flatMap { buildService.build(id: $0) }
    }

    private var isBuilding: Bool { currentBuild?.phase == .building }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field(title: "Dockerfile", caption: "The build file. Any filename works (Dockerfile, Containerfile, Dockerfile.dev, …).") {
                        HStack(spacing: 8) {
                            TextField("/path/to/Dockerfile", text: $dockerfile)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("build-image-dockerfile")
                            Button("Choose…") { chooseDockerfile() }
                        }
                    }

                    field(title: "Context Directory", caption: "The directory sent to the builder; COPY/ADD paths resolve against it. Defaults to the Dockerfile's folder.") {
                        HStack(spacing: 8) {
                            TextField("/path/to/project", text: $contextDir)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("build-image-context")
                            Button("Choose…") { chooseContextDir() }
                        }
                    }

                    field(title: "Image Name", caption: "Lowercase repository name with an optional :tag.") {
                        TextField("e.g., myapp:latest", text: $tag)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("build-image-tag")
                    }

                    field(title: "Platform", caption: arch == "amd64"
                            ? "Intel images build under Rosetta translation on Apple silicon."
                            : "Builds for the architecture this Mac runs natively.") {
                        Picker("", selection: $arch) {
                            Text("Apple silicon (linux/arm64)").tag("arm64")
                            Text("Intel (linux/amd64)").tag("amd64")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Toggle("Build without cache", isOn: $noCache)

                    if let validationError {
                        Text(validationError)
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let build = currentBuild {
                        BuildStatusLine(build: build)

                        LogConsoleView(lines: build.outputLines, filterText: "")
                            .frame(height: 220)
                            .background(Color.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding()
            }

            footer
        }
        .frame(width: 560, height: currentBuild == nil ? 520 : 700)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Build Image").font(.title2).fontWeight(.semibold)
            Spacer()
            Button(isBuilding ? "Close" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .help(isBuilding ? "The build keeps running; check on it from the Builds menu on the Images tab." : "")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)
    }

    private var footer: some View {
        HStack {
            Spacer()
            if isBuilding {
                Button("Cancel Build") {
                    currentBuildID.map { buildService.cancel($0) }
                }
            } else {
                if currentBuild?.phase == .succeeded {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Button(buildButtonTitle) { startBuild() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canBuild)
                    .keyboardShortcut(currentBuild?.phase == .succeeded ? nil : .defaultAction)
                    .accessibilityIdentifier("build-image-start")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
    }

    private var buildButtonTitle: String {
        switch currentBuild?.phase {
        case .failed, .cancelled: return "Retry Build"
        case .succeeded: return "Build Again"
        default: return "Build"
        }
    }

    @ViewBuilder
    private func field<Content: View>(title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canBuild: Bool {
        !dockerfile.trimmingCharacters(in: .whitespaces).isEmpty
            && !tag.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Panels

    private func chooseDockerfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true // .dockerignore neighbours, dotfile build files
        panel.message = "Choose a Dockerfile or Containerfile"
        let context = contextDir.trimmingCharacters(in: .whitespaces)
        if !context.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: context, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dockerfile = url.path
        if contextDir.trimmingCharacters(in: .whitespaces).isEmpty {
            contextDir = url.deletingLastPathComponent().path
        }
    }

    private func chooseContextDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the build context directory"
        let dockerfilePath = dockerfile.trimmingCharacters(in: .whitespaces)
        if !dockerfilePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: dockerfilePath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        contextDir = url.path
    }

    private func startBuild() {
        let request = ImageBuildService.Request(
            dockerfile: dockerfile.trimmingCharacters(in: .whitespaces),
            contextDir: contextDir.trimmingCharacters(in: .whitespaces),
            tag: tag.trimmingCharacters(in: .whitespaces),
            arch: arch,
            noCache: noCache
        )
        if let error = ImageBuildService.validationError(for: request) {
            validationError = error
            return
        }
        validationError = nil
        currentBuildID = buildService.startBuild(request)
    }
}

/// One-line status for a build record: spinner/check/cross plus a headline.
/// Shared by the Build Image sheet and the build log sheet.
struct BuildStatusLine: View {
    let build: ImageBuild

    var body: some View {
        switch build.phase {
        case .building:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Building… the first build also starts the BuildKit builder, which can take a minute.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .succeeded:
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Built \(build.tag)").font(.subheadline).fontWeight(.medium)
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                SwiftUI.Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .cancelled:
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "slash.circle").foregroundStyle(.secondary)
                Text("Build cancelled").font(.subheadline).foregroundStyle(.secondary)
            }
        case .interrupted:
            HStack(alignment: .top, spacing: 8) {
                SwiftUI.Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                Text("Interrupted: Orchard quit while this build was running. The image may still have been built.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
