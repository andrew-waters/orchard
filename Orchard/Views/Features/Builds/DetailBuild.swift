import SwiftUI

/// The Builds tab's detail column: one build's status and full log, live while
/// the build runs and reviewable after (including records restored from
/// previous launches).
struct BuildDetailView: View {
    @EnvironmentObject var buildService: ImageBuildService
    let buildID: UUID?

    private var build: ImageBuild? {
        buildID.flatMap { buildService.build(id: $0) }
    }

    var body: some View {
        if let build {
            VStack(spacing: 0) {
                header(for: build)

                BuildStatusLine(build: build)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if build.outputLines.isEmpty {
                    Text("No output yet")
                        .foregroundColor(Color(white: 0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.85))
                } else {
                    LogConsoleView(lines: build.outputLines, filterText: "")
                        .background(Color.black.opacity(0.85))
                }
            }
        } else {
            Text("Select a build")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for build: ImageBuild) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(build.tag)
                    .font(.title2).fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(build.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(BuildPhaseStyle.durationText(build.duration))
                    Text("·")
                    Text(build.request.arch == "amd64" ? "linux/amd64" : "linux/arm64")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                Text(build.request.dockerfile)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(build.request.dockerfile)
            }

            Spacer()

            if build.phase == .building {
                Button("Cancel Build") { buildService.cancel(build.id) }
                    .buttonStyle(BorderedButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
