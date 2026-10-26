import AppKit
import SwiftUI

/// Shown when there is no `container` binary to run (#145). Says what is missing and why
/// Orchard needs it, offers to install it, and always keeps the manual route in reach, so
/// declining or a failed install still leaves a way forward.
struct NotInstalledView: View {
    @EnvironmentObject var systemService: SystemService
    @EnvironmentObject var containerInstallService: ContainerInstallService
    @State private var showManual = false

    var body: some View {
        VStack(spacing: 28) {
            SwiftUI.Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Text("Apple container is not installed")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Orchard is a window onto Apple container, which runs the containers, images and machines it shows. Install container \(supportedContainerVersion) to get started.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            action

            manual
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            await systemService.checkSystemStatus()
        }
    }

    @ViewBuilder
    private var action: some View {
        if containerInstallService.currentStep != nil {
            progress
        } else {
            VStack(spacing: 12) {
                if let message = containerInstallService.failureMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if containerInstallService.wasDeclined {
                    Text("The install was cancelled. Try again, or install it yourself below.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    Button {
                        containerInstallService.beginInstall()
                    } label: {
                        Label(
                            containerInstallService.failureMessage == nil
                                ? "Install container \(supportedContainerVersion)" : "Try Again",
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Check Again") {
                        Task { @MainActor in await systemService.checkSystemStatus() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Text("Downloads Apple's signed installer from GitHub, then asks for an administrator password.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// The steps, ticked off as they pass, so a download on a slow connection does not look
    /// stuck and the password prompt arrives with its reason on screen.
    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ContainerInstallService.Step.allCases, id: \.rawValue) { step in
                row(for: step)
            }

            if containerInstallService.canCancel {
                Button("Cancel") { containerInstallService.cancelInstall() }
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 4)
            }
        }
        .frame(width: 360, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func row(for step: ContainerInstallService.Step) -> some View {
        let current = containerInstallService.currentStep?.rawValue ?? 0
        let isRunning = step.rawValue == current
        let isDone = step.rawValue < current

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

            Text(step.title)
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

    /// Opens by itself after a failure or a declined prompt, when it is the way forward.
    private var manual: some View {
        DisclosureGroup(isExpanded: Binding(
            get: {
                showManual || containerInstallService.failureMessage != nil || containerInstallService.wasDeclined
            },
            set: { showManual = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Download \(ContainerInstallService.packageName) from the container releases, then run:")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Text(ContainerInstallService.manualCommands)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)

                HStack {
                    Button("Copy") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(ContainerInstallService.manualCommands, forType: .string)
                    }
                    .controlSize(.small)

                    Spacer()

                    Link("Download the package", destination: ContainerInstallService.packageURL)
                        .font(.callout)
                    Link("Install instructions", destination: ContainerInstallService.instructionsURL)
                        .font(.callout)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        } label: {
            Text("Install it yourself")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: 480)
    }
}
