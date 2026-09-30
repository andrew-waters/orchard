import SwiftUI
import UniformTypeIdentifiers

/// Create a local Kubernetes cluster via `container k8s create`. Mirrors the CLI's
/// options: name, optional resource overrides, the Kubernetes version (as a node image),
/// and, under Advanced, a custom CNI manifest.
struct CreateClusterView: View {
    /// `pluginDefault` passes no `--node-image`, so the CLI uses its own default even when
    /// Orchard could not read which one that is.
    private enum NodeImageChoice: Hashable {
        case pluginDefault
        case image(String)
        case custom
    }

    @EnvironmentObject var clusterService: ClusterService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "k8s-dev"
    @State private var overrideResources: Bool = false
    @State private var cpus: Int = max(ProcessInfo.processInfo.processorCount / 2, 1)
    @State private var memoryGiB: Int = 4
    @State private var nodeImageChoice: NodeImageChoice = .pluginDefault
    @State private var customNodeImage: String = ""
    @State private var showAdvanced = false
    @State private var cniPath: String?
    @State private var validationError: String?

    private static let cniDocsURL = URL(string: "https://github.com/apple/container/blob/main/docs/kubernetes.md#custom-cni")!

    /// Set when recreating: the sheet opens filled in from the existing cluster, keeps its
    /// name, and its one button deletes and creates in a single step.
    private let recreating: ClusterRecreateSettings?

    init(recreating: ClusterRecreateSettings? = nil) {
        self.recreating = recreating
        guard let recreating else { return }
        _name = State(initialValue: recreating.name)
        _overrideResources = State(initialValue: true)
        _cpus = State(initialValue: recreating.cpus)
        _memoryGiB = State(initialValue: recreating.memoryGiB)
        switch recreating.nodeImage {
        case .pluginDefault:
            _nodeImageChoice = State(initialValue: .pluginDefault)
        case .reference(let reference):
            // Custom until the version list loads; `adoptListedVersion` then moves it onto
            // the matching menu entry if there is one.
            _nodeImageChoice = State(initialValue: .custom)
            _customNodeImage = State(initialValue: reference)
        case .untagged(let reference):
            _nodeImageChoice = State(initialValue: .custom)
            _customNodeImage = State(initialValue: reference)
            _validationError = State(initialValue: "Orchard doesn't know which version this cluster ran: its node records the image without a tag. Add the tag, or choose a version.")
        }
        _cniPath = State(initialValue: recreating.cni)
        _showAdvanced = State(initialValue: recreating.cni != nil)
    }

    private let hostCores = ProcessInfo.processInfo.processorCount
    private let hostGiB = max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if recreating != nil {
                        recreateNote
                    }

                    field(title: "Name", caption: "Lowercase letters, digits, and hyphens. The control-plane container takes this name.") {
                        TextField("k8s-dev", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(recreating != nil)
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

                    kubernetesVersionField

                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        cniField
                            .padding(.top, 8)
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
        .frame(width: 520, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await clusterService.loadNodeImageOptions()
            adoptListedVersion()
        }
    }

    /// A recreated cluster's image arrives as a custom reference; once the version list is
    /// in, show it as the menu entry it matches rather than as free text.
    private func adoptListedVersion() {
        guard nodeImageChoice == .custom else { return }
        if customNodeImage == clusterService.pluginDefaultNodeImage {
            nodeImageChoice = .pluginDefault
        } else if clusterService.nodeImageOptions.contains(where: { $0.reference == customNodeImage }) {
            nodeImageChoice = .image(customNodeImage)
        }
    }

    private var recreateNote: some View {
        HStack(alignment: .top, spacing: 8) {
            SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Recreating deletes \(name) and creates it again with these settings. Workloads and images loaded into it are not kept.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Kubernetes version

    private var pluginDefaultLabel: String {
        guard let reference = clusterService.pluginDefaultNodeImage,
              let tag = K8sNodeImageCatalog.tag(of: reference)
        else { return "Plugin Default" }
        return "\(tag) (Recommended)"
    }

    /// The fetched versions, less the plugin default's exact image, which already heads the list.
    private var otherVersions: [K8sNodeImageOption] {
        clusterService.nodeImageOptions.filter { $0.reference != clusterService.pluginDefaultNodeImage }
    }

    private var kubernetesVersionField: some View {
        field(
            title: "Kubernetes Version",
            caption: "Recommended is the node image Apple container's k8s plugin ships with and is tested against. Others are the newest kindest/node release of each version from 1.31."
        ) {
            Picker("Kubernetes Version", selection: $nodeImageChoice) {
                Text(pluginDefaultLabel).tag(NodeImageChoice.pluginDefault)
                if !otherVersions.isEmpty {
                    Divider()
                    ForEach(otherVersions) { option in
                        Text(option.version).tag(NodeImageChoice.image(option.reference))
                    }
                }
                Divider()
                Text("Custom Image…").tag(NodeImageChoice.custom)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)

            if nodeImageChoice == .custom {
                TextField("docker.io/kindest/node:v1.34.11", text: $customNodeImage)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - CNI

    private var cniField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CNI Manifest (Optional)").font(.headline)
            HStack {
                Text(cniPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Default (kindnet)")
                    .foregroundStyle(cniPath == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(cniPath ?? "")
                Spacer()
                if cniPath != nil {
                    Button("Clear") { cniPath = nil }
                }
                Button("Choose…") { chooseCNIManifest() }
            }
            Text("Applied instead of kindnet once the control plane is up. It must fit the cluster's pod subnet, or the cluster never becomes ready.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Custom CNI in Apple container's docs", destination: Self.cniDocsURL)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseCNIManifest() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml"), .json]
            .compactMap { $0 }
        panel.message = "Choose a Kubernetes manifest for the cluster's CNI"
        if panel.runModal() == .OK, let url = panel.url {
            cniPath = url.path
        }
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
            Text(recreating == nil ? "Create Cluster" : "Recreate Cluster").font(.title2).fontWeight(.semibold)
            Spacer()
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
            Button(submitTitle) { create() }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || clusterService.isCreating || clusterService.busyClusters.contains(name))
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

    private var submitTitle: String {
        if clusterService.isCreating { return recreating == nil ? "Creating…" : "Recreating…" }
        return recreating == nil ? "Create Cluster" : "Recreate Cluster"
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

        let nodeImage: String?
        switch nodeImageChoice {
        case .pluginDefault:
            nodeImage = nil
        case .image(let reference):
            nodeImage = reference
        case .custom:
            let trimmedImage = customNodeImage.trimmingCharacters(in: .whitespaces)
            // 1.5.0 refuses an untagged image, since the tag is where the Kubernetes version
            // comes from; saying so here saves booting nothing.
            guard !trimmedImage.isEmpty, K8sNodeImageCatalog.tag(of: trimmedImage) != nil else {
                validationError = "Include a tag in the node image, such as docker.io/kindest/node:v1.34.11. Apple container reads the Kubernetes version from it."
                return
            }
            nodeImage = trimmedImage
        }
        validationError = nil

        Task {
            let cpus = overrideResources ? cpus : nil
            let memory = overrideResources ? "\(memoryGiB)GB" : nil
            let created: Bool
            if recreating == nil {
                created = await clusterService.create(name: trimmedName, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cniPath)
            } else {
                created = await clusterService.recreate(name: trimmedName, cpus: cpus, memory: memory, nodeImage: nodeImage, cni: cniPath)
            }
            if created { await MainActor.run { dismiss() } }
        }
    }
}
