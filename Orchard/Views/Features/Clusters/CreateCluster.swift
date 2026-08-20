import SwiftUI

/// Create a local Kubernetes cluster via `container k8s create`. Mirrors the CLI's
/// options: name, optional resource overrides, and an optional node image.
struct CreateClusterView: View {
    @EnvironmentObject var clusterService: ClusterService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "k8s-dev"
    @State private var overrideResources: Bool = false
    @State private var cpus: Int = max(ProcessInfo.processInfo.processorCount / 2, 1)
    @State private var memoryGiB: Int = 4
    @State private var nodeImage: String = ""
    @State private var validationError: String?

    private let hostCores = ProcessInfo.processInfo.processorCount
    private let hostGiB = max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field(title: "Name", caption: "Lowercase letters, digits, and hyphens. The control-plane container takes this name.") {
                        TextField("k8s-dev", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Override resource defaults", isOn: $overrideResources)
                        Text("Off: the runtime picks CPU and memory defaults for the node.")
                            .font(.caption).foregroundStyle(.secondary)

                        if overrideResources {
                            HStack(alignment: .top, spacing: 16) {
                                field(title: "CPUs", caption: "Cores allocated (host has \(hostCores)).") {
                                    NumericStepperField(value: $cpus, range: 1...hostCores)
                                }
                                field(title: "Memory (GB)", caption: "RAM allocated (host has \(hostGiB) GB).") {
                                    NumericStepperField(value: $memoryGiB, range: 1...hostGiB, unit: "GB")
                                }
                            }
                        }
                    }

                    field(title: "Node Image (Optional)", caption: "A kindest/node image reference. Leave empty for the runtime default.") {
                        TextField("docker.io/kindest/node:…", text: $nodeImage)
                            .textFieldStyle(.roundedBorder)
                    }

                    slownessNote

                    if let validationError {
                        Text(validationError)
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }

            footer
        }
        .frame(width: 520, height: 440)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var slownessNote: some View {
        HStack(alignment: .top, spacing: 8) {
            SwiftUI.Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text("Creating a cluster pulls the Kubernetes node image on first use and bootstraps the control plane. This can take several minutes; the cluster appears in the list when it's ready.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack {
            Text("Create Cluster").font(.title2).fontWeight(.semibold)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)
    }

    private var footer: some View {
        HStack {
            if clusterService.isCreating {
                ProgressView().controlSize(.small)
                Text("Creating cluster…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(clusterService.isCreating ? "Creating…" : "Create Cluster") { create() }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || clusterService.isCreating)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
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

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // Cluster names become container IDs; same rule as machines for a fast, clear message.
        let pattern = "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
        guard trimmedName.range(of: pattern, options: .regularExpression) != nil else {
            validationError = "Invalid name. Use lowercase letters, digits, and hyphens (must start and end alphanumeric)."
            return
        }
        validationError = nil

        let trimmedImage = nodeImage.trimmingCharacters(in: .whitespaces)
        Task {
            let created = await clusterService.create(
                name: trimmedName,
                cpus: overrideResources ? cpus : nil,
                memory: overrideResources ? "\(memoryGiB)GB" : nil,
                nodeImage: trimmedImage.isEmpty ? nil : trimmedImage
            )
            if created { await MainActor.run { dismiss() } }
        }
    }
}
