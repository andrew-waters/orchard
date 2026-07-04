import SwiftUI
import AppKit

struct RunContainerView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @Environment(\.dismiss) var dismiss

    let imageName: String
    @State private var config: ContainerRunConfig
    @State private var isRunning = false
    @State private var nameValidationError: String?

    init(imageName: String) {
        self.imageName = imageName

        // Generate a default container name from the image
        let cleanName = imageName
            .replacingOccurrences(of: "docker.io/library/", with: "")
            .replacingOccurrences(of: "docker.io/", with: "")
            .split(separator: ":").first.map(String.init) ?? "container"

        _config = State(initialValue: ContainerRunConfig(name: cleanName, image: imageName))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ContainerConfigForm(config: $config, nameValidationError: $nameValidationError, mode: .run)
            Divider()
            footerView
        }
        .frame(width: 700, height: 600)
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

                Text(imageName)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            .disabled(config.name.isEmpty || isRunning || nameValidationError != nil)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func runContainer() {
        // Re-validate before running.
        nameValidationError = ContainerConfigForm.validationError(
            for: config.name, existing: containerListService.containers
        )
        guard nameValidationError == nil else { return }

        isRunning = true
        Task {
            await containerListService.runContainer(config: config)
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
