import SwiftUI

/// Installing the `container compose` CLI plugin, with the work shown.
///
/// A modal rather than a line in the banner because this reaches out to the network, unpacks
/// an archive and then asks for an administrator password. Someone who is about to be asked
/// for their password should be able to see what asked and why, and a 15MB download behind a
/// four-pixel spinner gives them nothing to judge it by.
///
/// The work starts as the sheet appears. There is no second confirmation here: the button in
/// the banner was the decision, and asking twice for the same thing is its own annoyance.
struct InstallComposePluginSheet: View {
    @EnvironmentObject var composePluginService: ComposePluginService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            steps
            Divider()
            footer
        }
        .frame(width: 460)
        .task {
            // Only start a fresh run: reopening the sheet over a finished install should show
            // the result, not do it again.
            if composePluginService.isMissing { composePluginService.beginInstall() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Install container compose")
                .font(.title2.weight(.semibold))
            Text("Fetches the latest release and puts it where the container CLI looks.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ComposePluginService.Step.allCases, id: \.rawValue) { step in
                row(for: step)
            }

            if let version = composePluginService.installedVersion, !composePluginService.isWorking {
                Label(
                    "Installed \(version). `container compose up` now works in a terminal.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.green)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let message = composePluginService.failureMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One step, marked done, running, or still to come.
    private func row(for step: ComposePluginService.Step) -> some View {
        let current = composePluginService.currentStep
        let isDone = isPast(step, current: current)
        let isRunning = current == step

        return HStack(spacing: 10) {
            Group {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else if isDone {
                    SwiftUI.Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    SwiftUI.Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16, height: 16)

            Text(title(for: step))
                .font(.callout)
                .foregroundStyle(isDone || isRunning ? .primary : .secondary)

            if isRunning, let note = step.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    /// A step is done when the run has moved past it, or when the whole thing finished.
    private func isPast(_ step: ComposePluginService.Step, current: ComposePluginService.Step?) -> Bool {
        if let current { return step.rawValue < current.rawValue }
        return composePluginService.installedVersion != nil && composePluginService.failureMessage == nil
    }

    /// The download step names the version once it is known, so the sheet says what it is
    /// fetching rather than just that it is fetching.
    private func title(for step: ComposePluginService.Step) -> String {
        guard step == .downloading, let version = composePluginService.targetVersion else {
            return step.title
        }
        return "\(step.title) \(version)"
    }

    private var footer: some View {
        HStack {
            Spacer()
            if composePluginService.isWorking {
                Button("Cancel") {
                    composePluginService.cancelInstall()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
