import SwiftUI

// MARK: - Network Detail Header
struct NetworkDetailHeader: View {
    let network: ContainerNetwork

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(network.id)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Add network-specific actions here if needed in the future
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
    }
}
