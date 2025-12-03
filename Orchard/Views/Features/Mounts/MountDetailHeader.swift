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
            HStack(spacing: 12) {
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mount.mount.source))
                }) {
                    Label("Open in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
