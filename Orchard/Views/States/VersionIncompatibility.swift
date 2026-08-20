import SwiftUI

struct VersionIncompatibilityView: View {
    @EnvironmentObject var systemService: SystemService
    var body: some View {
        VStack(spacing: 30) {
            SwiftUI.Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 16) {
                Text("Unsupported Container Version")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("This build of Orchard talks to Apple container \(supportedContainerVersion), but the installed container service is a different release the app can't communicate with.")
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)

                if let detail = systemService.systemStatusError {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Text("Update your container installation (or Orchard) so the versions match, then check again.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: 16) {
                Button("View upgrade instructions") {
                    if let url = URL(string: "https://github.com/apple/container?tab=readme-ov-file#install-or-upgrade") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Check Again") {
                    Task { @MainActor in
                        await systemService.checkSystemStatus()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            await systemService.checkSystemStatus()
        }
    }
}
