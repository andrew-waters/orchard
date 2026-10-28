import SwiftUI

/// Creates a named volume, as `container volume create [-s size] [--label k=v] name` does.
/// Used from the Volumes tab and from a mount row in the run and edit forms.
struct AddVolumeView: View {
    @EnvironmentObject var volumeService: VolumeService
    @Environment(\.dismiss) private var dismiss

    /// Called with the volume once it exists, before the sheet closes.
    var onCreated: (ContainerVolume) -> Void = { _ in }

    @State private var name = ""
    @State private var size = ""
    @State private var labels: [ContainerRunConfig.LabelPair] = []
    @State private var isCreating = false
    /// Why the input or the runtime refused, shown in the sheet: the app's alert can't
    /// appear over a sheet.
    @State private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedSize: String { size.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create Volume")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("e.g. pgdata", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("add-volume-name")
                        Text(InputValidation.invalidVolumeNameMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Size (Optional)")
                            .font(.headline)
                        TextField("e.g. 10G", text: $size)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Text("The most the volume can hold, such as 512M or 10G. It takes space on disk only as it fills. Leave empty for the runtime's default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    labelsSection

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isCreating ? "Creating..." : "Create Volume") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty || isCreating)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
        }
        .frame(width: 480, height: 440)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Labels (Optional)")
                    .font(.headline)
                Spacer()
                Button("Add Label") { labels.append(.init(key: "", value: "")) }
                    .buttonStyle(.borderless)
            }
            if labels.isEmpty {
                Text("No labels added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($labels) { $pair in
                    LabelPairRow(pair: $pair) { labels.removeAll { $0.id == pair.id } }
                }
            }
        }
    }

    private func create() {
        guard InputValidation.isValidVolumeName(trimmedName) else {
            error = "Invalid volume name. \(InputValidation.invalidVolumeNameMessage)"
            return
        }
        if !trimmedSize.isEmpty && InputValidation.volumeSizeBytes(trimmedSize) == nil {
            error = "Invalid size. \(InputValidation.invalidVolumeSizeMessage)"
            return
        }
        if labels.contains(where: { $0.key.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.isEmpty }) {
            error = "A label with a value needs a key."
            return
        }
        if volumeService.volumes.contains(where: { $0.name == trimmedName }) {
            error = "A volume named \(trimmedName) already exists."
            return
        }

        var labelDict: [String: String] = [:]
        for pair in labels {
            let key = pair.key.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { labelDict[key] = pair.value.trimmingCharacters(in: .whitespaces) }
        }

        error = nil
        isCreating = true
        Task {
            do {
                let volume = try await volumeService.create(
                    name: trimmedName,
                    size: trimmedSize.isEmpty ? nil : trimmedSize,
                    labels: labelDict
                )
                onCreated(volume)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isCreating = false
        }
    }
}
