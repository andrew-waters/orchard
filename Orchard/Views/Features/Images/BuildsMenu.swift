import SwiftUI

/// The menu-bar "Builds" menu: every build Orchard has started, current and
/// restored from previous launches (the builder shim exposes no host-reachable
/// BuildKit history, so builds Orchard didn't start can't be listed). Each
/// build's submenu opens its log window or cancels it; logs of finished and
/// interrupted builds stay reviewable until cleared.
struct BuildsMenuCommands: View {
    @ObservedObject var buildService: ImageBuildService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Build an Image…") {
            NotificationCenter.default.post(name: NSNotification.Name("ShowBuildImageSheet"), object: nil)
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])

        Divider()

        if buildService.builds.isEmpty {
            Text("No Builds Recorded")
        } else {
            ForEach(buildService.builds) { build in
                Menu {
                    Text(subtitle(for: build))
                    Divider()
                    Button("Show Log") {
                        openWindow(id: "build-log", value: build.id)
                    }
                    if build.phase == .building {
                        Button("Cancel Build") {
                            buildService.cancel(build.id)
                        }
                    }
                } label: {
                    Label(build.tag, systemImage: icon(for: build.phase))
                }
            }

            Divider()

            Button("Clear Finished") { buildService.clearFinished() }
                .disabled(!buildService.builds.contains { $0.phase.isFinished })
        }
    }

    private func icon(for phase: ImageBuild.Phase) -> String {
        switch phase {
        case .building: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "slash.circle"
        case .interrupted: return "questionmark.circle"
        }
    }

    private func subtitle(for build: ImageBuild) -> String {
        let when = build.startedAt.formatted(date: .abbreviated, time: .shortened)
        switch build.phase {
        case .building: return "Building since \(when)"
        case .succeeded: return "Succeeded · \(when) · \(durationText(build.duration))"
        case .failed: return "Failed · \(when) · \(durationText(build.duration))"
        case .cancelled: return "Cancelled · \(when)"
        case .interrupted: return "Interrupted by app quit · \(when)"
        }
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

/// The full log of one build, in its own window so it is reachable from the
/// Builds menu; live while the build runs, static once it finishes.
struct BuildLogWindow: View {
    @EnvironmentObject var buildService: ImageBuildService
    let buildID: UUID?

    private var build: ImageBuild? {
        buildID.flatMap { buildService.build(id: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let build {
                HStack {
                    Text(build.tag)
                        .font(.title3).fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if build.phase == .building {
                        Button("Cancel Build") { buildService.cancel(build.id) }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)

                BuildStatusLine(build: build)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                LogConsoleView(lines: build.outputLines, filterText: "")
                    .background(Color.black.opacity(0.85))
            } else {
                Text("This build is no longer recorded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(build.map { "Build · \($0.tag)" } ?? "Build")
    }
}
