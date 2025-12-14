import SwiftUI

struct NewerVersionView: View {
    @EnvironmentObject var containerService: ContainerService

    var body: some View {
        VStack(spacing: 30) {
            SwiftUI.Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 16) {
                Text("Container's Version is not yet supported")
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

                Text("Please check whether an Orchard update is available.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: 16) {
                Button("Check latest Orchard releases") {
                    if let url = URL(string: "https://github.com/andrew-waters/orchard/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Proceed Anyway") {
                    Task { @MainActor in
                        await containerService.checkSystemStatusIgnoreVersion()
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
