import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var isInitialLoadComplete: Bool

    private var windowTitle: String {
        if let version = containerService.parsedContainerVersion {
            return "Container \(version)"
        }
        return "Container"
    }

    var body: some View {
        VStack(spacing: 20) {
            // App icon or logo
            SwiftUI.Image(systemName: "cube.box.fill")
                .font(.system(size: 80))
                .foregroundColor(.white)

            Text(windowTitle)
                .font(.title)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.0, green: 0.3, blue: 0.6))
        .task {
            await performInitialLoad()
            isInitialLoadComplete = true
        }
    }

    private func performInitialLoad() async {
        await containerService.checkSystemStatus()
        await containerService.loadContainers(showLoading: true)
        await containerService.loadImages()
        await containerService.loadBuilders()

        await containerService.loadDNSDomains(showLoading: true)
        await containerService.loadNetworks(showLoading: true)

        // Check for updates on startup
        if containerService.shouldCheckForUpdates() {
            await containerService.checkForUpdates()
        }
    }
}
