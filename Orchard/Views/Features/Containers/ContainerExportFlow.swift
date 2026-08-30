import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The shared export gesture (detail header button, list context menu): ask for
/// a destination, export the container's filesystem via the backend, and reveal
/// the archive in Finder. Failures alert through the service.
@MainActor
enum ContainerExportFlow {
    static func run(containerId: String, service: ContainerListService) {
        let panel = NSSavePanel()
        panel.title = "Export Container"
        panel.message = "Save '\(containerId)' filesystem as a tar archive"
        panel.nameFieldStringValue = "\(containerId).tar"
        panel.allowedContentTypes = [UTType(filenameExtension: "tar") ?? .data]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if await service.exportContainer(containerId, to: url) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
