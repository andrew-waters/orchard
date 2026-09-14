import AppKit
import ComposeModel
import SwiftUI
import UniformTypeIdentifiers

/// Choosing a compose file. Main-actor, because a panel is a window.
@MainActor
enum ComposeAddFlow {
    static func present(service: ComposeService) {
        let panel = NSOpenPanel()
        panel.message = "Choose a compose file"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.yaml]
        if let yml = UTType(filenameExtension: "yml") { types.append(yml) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        service.beginAdd(fileURL: url)
    }
}

/// What a file asks for that Orchard will not do, put in front of someone before anything is
/// created.
///
/// The plugin refuses a file like this outright, because a command in a script has nobody to
/// ask. A window does have somebody to ask, so this asks, and the project then carries what
/// was accepted for as long as it exists. Three weeks later nobody remembers what they agreed
/// to, and the containers cannot tell them.
struct ComposeReviewSheet: View {
    @EnvironmentObject var composeService: ComposeService
    @Environment(\.dismiss) private var dismiss

    let preview: ComposeFilePreview
    /// True when the project is already known and the file has simply moved on.
    let isRevision: Bool

    private var blocking: [Finding] { preview.blockingFindings }
    private var cosmetic: [Finding] { preview.cosmeticFindings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !blocking.isEmpty {
                        section(
                            title: "Will not be honoured",
                            note: "These change what your services do. Orchard will create everything else and leave these out.",
                            findings: blocking,
                            tint: .orange
                        )
                    }
                    if !cosmetic.isEmpty {
                        section(
                            title: "Ignored",
                            note: "Read and stepped over. Nothing about the running services depends on them.",
                            findings: cosmetic,
                            tint: .secondary
                        )
                    }
                    if !preview.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Variables with no value")
                                .font(.headline)
                            Text("Substituted with an empty string, which is what compose does.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(preview.warnings) { warning in
                                Text(warning.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if blocking.isEmpty && cosmetic.isEmpty && preview.warnings.isEmpty {
                        Label(
                            "Everything in this file is supported.",
                            systemImage: "checkmark.circle"
                        )
                        .foregroundStyle(.green)
                    }
                    servicesSection
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preview.identity.name)
                .font(.title2.weight(.semibold))
            Text(preview.fileURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func section(title: String, note: String, findings: [Finding], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(findings) { finding in
                HStack(alignment: .top, spacing: 8) {
                    SwiftUI.Image(systemName: finding.severity == .behavioural ? "exclamationmark.triangle.fill" : "minus.circle")
                        .foregroundStyle(tint)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(finding.message)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Services")
                .font(.headline)
            Text(preview.serviceNames.joined(separator: ", "))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(addTitle) {
                if isRevision {
                    composeService.acknowledgeFindings(for: preview.identity.name)
                } else {
                    composeService.add(preview)
                    composeService.selectedProject = preview.identity.name
                }
                composeService.clearPendingPreview()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var addTitle: String {
        if isRevision { return blocking.isEmpty ? "Got It" : "Accept Changes" }
        return blocking.isEmpty ? "Add Project" : "Add Anyway"
    }
}
