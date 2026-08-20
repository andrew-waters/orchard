import AppKit
import SwiftUI

struct NotRunningView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var imageService: ImageService
    @EnvironmentObject var builderService: BuilderService
    @EnvironmentObject var systemService: SystemService
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 20) {
            PowerButton(
                isLoading: systemService.isSystemLoading,
                action: {
                    Task { @MainActor in
                        await systemService.startSystem()
                    }
                }
            )

            Text("Container is not currently runnning")
                .font(.title2)
                .fontWeight(.medium)

            if let error = systemService.systemStatusError {
                DisclosureGroup(isExpanded: $showDiagnostics) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Copy") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(error, forType: .string)
                        }
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                } label: {
                    Text("Diagnostics")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 480)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            await systemService.checkSystemStatus()
        }
    }
}
