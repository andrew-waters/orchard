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
                DetailViewButton.openInFinder(
                    action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: mount.mount.source))
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
    }
}
