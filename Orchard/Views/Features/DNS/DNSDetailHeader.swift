import SwiftUI

// MARK: - DNS Detail Header
struct DNSDetailHeader: View {
    let domain: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(domain)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Add DNS-specific actions here if needed in the future
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Rectangle())
    }
}
