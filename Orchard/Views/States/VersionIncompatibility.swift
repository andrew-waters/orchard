import SwiftUI

struct VersionIncompatibilityView: View {
    @EnvironmentObject var containerService: ContainerService

    var body: some View {
        VStack(spacing: 30) {
            SwiftUI.Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 16) {
                Text("Unsupported Container Version")
                    .font(.title)
                    .fontWeight(.semibold)

                if let installedVersion = containerService.parsedContainerVersion {
                    Text("We require Apple Container version \(containerService.supportedContainerVersion), but you are running version \(installedVersion)")
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                } else if let rawVersion = containerService.containerVersion {
                    Text("Detected version: \(rawVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)

                    Text("We require Apple Container version \(containerService.supportedContainerVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("We require Apple Container version \(containerService.supportedContainerVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Please update your Container installation to continue using this application.")
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
                        await containerService.checkSystemStatus()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            await containerService.checkSystemStatus()
        }
    }
}
