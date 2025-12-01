import SwiftUI

// MARK: - Image Detail Header
struct ImageDetailHeader: View {
    let image: ContainerImage
    @EnvironmentObject var containerService: ContainerService
    @State private var showRunContainer = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isRunning = false

    private var imageName: String {
        let components = image.reference.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent.split(separator: ":").first ?? lastComponent)
        }
        return image.reference
    }

    private var containersUsingImage: [Container] {
        containerService.containers.filter { container in
            container.configuration.image.reference == image.reference
        }
    }

    private func deleteImage() {
        isDeleting = true
        Task {
            await containerService.deleteImage(image.reference)
            await MainActor.run {
                isDeleting = false
            }
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(imageName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Run Container button
                DetailViewButton(
                    icon: "plus",
                    accessibilityText: "Create a container using this image",
                    action: {
                        showRunContainer = true
                    },
                )

                // Delete Image button - only show if no containers are using it
                if containersUsingImage.isEmpty {
                    DetailViewButton(
                        icon: "trash.fill",
                        accessibilityText: "Delete Image",
                        action: {
                            showDeleteConfirmation = true
                        },
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(.regularMaterial, in: Rectangle())
        .sheet(isPresented: $showRunContainer) {
            RunContainerView(imageName: image.reference)
                .environmentObject(containerService)
        }
        .alert("Delete Image?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteImage()
            }
        } message: {
            Text("Are you sure you want to delete '\(imageName)'? This action cannot be undone.")
        }
    }
}
