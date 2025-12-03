import SwiftUI

// MARK: - Configuration Detail Header
struct ConfigurationDetailHeader: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Configuration")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Add configuration-specific actions here if needed in the future
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
