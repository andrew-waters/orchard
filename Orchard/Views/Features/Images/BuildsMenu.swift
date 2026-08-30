import SwiftUI

/// Toolbar affordance on the Images tab: lists every build this app session
/// has started (the builder shim exposes no host-reachable history, so builds
/// Orchard didn't start can't be shown). Running builds get a count badge on
/// the button; each row can reopen its live log or cancel.
struct BuildsMenuButton: View {
    @EnvironmentObject var buildService: ImageBuildService
    @State private var showPopover = false
    @State private var logTarget: BuildLogTarget?

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            ZStack(alignment: .topTrailing) {
                SwiftUI.Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.primary)
                    .font(.system(size: 14, weight: .medium))
                if buildService.runningCount > 0 {
                    Text("\(buildService.runningCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 7, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("images-builds-menu")
        .help("Builds")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            BuildsListPopover { buildID in
                showPopover = false
                logTarget = BuildLogTarget(id: buildID)
            }
        }
        .sheet(item: $logTarget) { target in
            BuildLogSheet(buildID: target.id)
        }
    }
}

struct BuildLogTarget: Identifiable {
    let id: UUID
}

struct BuildsListPopover: View {
    @EnvironmentObject var buildService: ImageBuildService
    /// Called with the build to open in the log sheet (the popover closes).
    let onOpenLog: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Builds")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            if buildService.builds.isEmpty {
                Text("No builds this session.\nUse the hammer button to build an image from a Dockerfile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(buildService.builds) { build in
                            row(build)
                            if build.id != buildService.builds.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                Spacer()
                Button("Clear Finished") { buildService.clearFinished() }
                    .controlSize(.small)
                    .disabled(!buildService.builds.contains { $0.phase.isFinished })
            }
            .padding(8)
        }
        .frame(width: 360)
    }

    private func row(_ build: ImageBuild) -> some View {
        HStack(spacing: 10) {
            statusIcon(build.phase)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(build.tag)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(build.startedAt, style: .relative)
                    Text("ago ·")
                    Text(durationText(build.duration))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onOpenLog(build.id)
            } label: {
                SwiftUI.Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show build log")

            if build.phase == .building {
                Button {
                    buildService.cancel(build.id)
                } label: {
                    SwiftUI.Image(systemName: "stop.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cancel build")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusIcon(_ phase: ImageBuild.Phase) -> some View {
        switch phase {
        case .building:
            ProgressView().controlSize(.small)
        case .succeeded:
            SwiftUI.Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            SwiftUI.Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .cancelled:
            SwiftUI.Image(systemName: "slash.circle").foregroundStyle(.secondary)
        }
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

/// The full log of one build, reopenable from the Builds menu while the build
/// runs or after it finishes.
struct BuildLogSheet: View {
    @EnvironmentObject var buildService: ImageBuildService
    @Environment(\.dismiss) private var dismiss
    let buildID: UUID

    private var build: ImageBuild? {
        buildService.build(id: buildID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(build?.tag ?? "Build")
                    .font(.title3).fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)

            if let build {
                BuildStatusLine(build: build)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                LogConsoleView(lines: build.outputLines, filterText: "")
                    .background(Color.black.opacity(0.85))
            } else {
                Text("This build is no longer in the list.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Spacer()
                if build?.phase == .building {
                    Button("Cancel Build") { buildService.cancel(buildID) }
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
        }
        .frame(width: 680, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
