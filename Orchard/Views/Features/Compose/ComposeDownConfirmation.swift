import ComposePlanner
import SwiftUI

/// Down for a project that has volumes asks whether to keep them (#162). Keeping is the
/// default, because a volume is where the data is; a project with none goes down at once.
struct ComposeDownConfirmation: ViewModifier {
    /// The project waiting on an answer. Set through `ComposeDown.request`.
    @Binding var project: ComposeProject?

    @EnvironmentObject var composeService: ComposeService
    @EnvironmentObject var volumeService: VolumeService

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { project != nil }, set: { if !$0 { project = nil } }),
            presenting: project
        ) { project in
            // With the containers already gone, keeping the volumes would be a Down that does
            // nothing, so the only choices are to remove them or not.
            if !project.containers.isEmpty {
                Button("Keep Volumes") {
                    Task { await composeService.down(project: project) }
                }
                .keyboardShortcut(.defaultAction)
            }
            Button("Remove Volumes", role: .destructive) {
                Task { await composeService.down(project: project, options: DownOptions(removeVolumes: true)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(message(for: project))
        }
    }

    private var title: String {
        let name = project?.name ?? ""
        return project?.containers.isEmpty == true ? "Remove the volumes '\(name)' kept?" : "Take '\(name)' down?"
    }

    private func message(for project: ComposeProject) -> String {
        let names = ComposeProjectVolume.labelled(project.name, in: volumeService.volumes).map(\.name)
        let volumes = (names.count == 1 ? "a volume" : "\(names.count) volumes")
            + ", \(ListFormatter.localizedString(byJoining: names))"
        if project.containers.isEmpty {
            return "Its containers are already gone. It still has \(volumes). Removing "
                + (names.count == 1 ? "it" : "them") + " deletes the data in "
                + (names.count == 1 ? "it" : "them") + ", which can't be got back."
        }
        return "Its containers are stopped and removed. It has \(volumes), which can be kept for the "
            + "next Up or removed with the data in them, which can't be got back."
    }
}

enum ComposeDown {
    /// Whether Down has anything to do: containers to remove, or volumes a Down that kept them
    /// left behind, which a later Down can still remove.
    static func isAvailable(for project: ComposeProject, volumes: [ContainerVolume]) -> Bool {
        !project.containers.isEmpty || !ComposeProjectVolume.labelled(project.name, in: volumes).isEmpty
    }

    /// Take a project down, asking first when it has volumes.
    @MainActor
    static func request(
        _ project: ComposeProject,
        composeService: ComposeService,
        volumeService: VolumeService,
        pending: Binding<ComposeProject?>
    ) {
        if ComposeProjectVolume.labelled(project.name, in: volumeService.volumes).isEmpty {
            Task { await composeService.down(project: project) }
        } else {
            pending.wrappedValue = project
        }
    }
}

extension View {
    func composeDownConfirmation(_ project: Binding<ComposeProject?>) -> some View {
        modifier(ComposeDownConfirmation(project: project))
    }
}
