import SwiftUI

// MARK: - Mount Detail Header
struct MountDetailHeader: View {
    let mount: ContainerMount

    private var mountName: String {
        URL(fileURLWithPath: mount.mount.source).lastPathComponent
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mountName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mount.mount.source))
                }) {
                    SwiftUI.Image(systemName: "folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Open in Finder")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
    }
}
