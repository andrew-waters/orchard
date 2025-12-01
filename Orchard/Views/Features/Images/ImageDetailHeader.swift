import SwiftUI

// MARK: - Image Detail Header
struct ImageDetailHeader: View {
    let image: ContainerImage
    @EnvironmentObject var containerService: ContainerService
    @State private var showRunContainer = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

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
                Button(action: {
                    showRunContainer = true
                }) {
                    HStack(spacing: 6) {
                        SwiftUI.Image(systemName: "play.circle.fill")
                        Text("Run Container")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDeleting)

                // Delete Image button - only show if no containers are using it
                if containersUsingImage.isEmpty {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack(spacing: 6) {
                            if isDeleting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                SwiftUI.Image(systemName: "trash")
                            }
                            Text(isDeleting ? "Deleting..." : "Delete")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(isDeleting)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
