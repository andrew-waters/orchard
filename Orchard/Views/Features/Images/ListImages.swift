import SwiftUI

struct ImagesListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedImage: String?
    @Binding var lastSelectedImage: String?
    @Binding var searchText: String
    @Binding var showOnlyImagesInUse: Bool
    @Binding var showImageSearch: Bool
    @AppStorage("imageSortBy") private var sortBy: ImageSortOption = .name
    @AppStorage("imageSortAscending") private var sortAscending: Bool = true
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            imagesList
        }
        .sheet(isPresented: $showImageSearch) {
            ImageSearchView()
                .environmentObject(containerService)
        }
    }

    private var imagesList: some View {
        List(selection: $selectedImage) {
            ForEach(Array(filteredImages), id: \.reference) { image in
                imageRowView(for: image)
            }
        }
        .listStyle(PlainListStyle())
        .animation(.easeInOut(duration: 0.3), value: containerService.images)
        .focused($listFocusedTab, equals: .images)
        .onChange(of: selectedImage) { _, newValue in
            lastSelectedImage = newValue
        }
    }

    private func imageRowView(for image: ContainerImage) -> some View {
        let imageName = imageName(from: image.reference)
        let imageTag = imageTag(from: image.reference)
        let sizeText = ByteCountFormatter().string(fromByteCount: Int64(image.descriptor.size))

        return ListItemRow(
            icon: "cube.transparent",
            iconColor: isImageInUseByRunningContainer(image) ? .green : .secondary,
            primaryText: imageName,
            secondaryLeftText: imageTag,
            secondaryRightText: sizeText,
            isSelected: selectedImage == image.reference
        )
        .contextMenu {
            Button("Copy Image Reference") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(image.reference, forType: .string)
            }

            Divider()

            Button("Remove Image", role: .destructive) {
                Task {
                    await containerService.deleteImage(image.reference)
                }
            }
        }
        .tag(image.reference)
    }



    private func imageName(from reference: String) -> String {
        let components = reference.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent.split(separator: ":").first ?? lastComponent)
        }
        return reference
    }

    private func imageTag(from reference: String) -> String {
        if let tagComponent = reference.split(separator: ":").last,
           tagComponent != reference.split(separator: "/").last {
            return String(tagComponent)
        }
        return "latest"
    }

    private var filteredImages: [ContainerImage] {
        var filtered = containerService.images

        // Apply "in use" filter
        if showOnlyImagesInUse {
            filtered = filtered.filter { image in
                containerService.containers.contains { container in
                    container.configuration.image.reference == image.reference
                }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { image in
                image.reference.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply sort
        let ascending = sortAscending
        switch sortBy {
        case .name:
            filtered.sort {
                let result = imageName(from: $0.reference).localizedCaseInsensitiveCompare(imageName(from: $1.reference))
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        case .tag:
            filtered.sort { ascending ? imageTag(from: $0.reference) < imageTag(from: $1.reference) : imageTag(from: $0.reference) > imageTag(from: $1.reference) }
        case .size:
            filtered.sort { ascending ? $0.descriptor.size < $1.descriptor.size : $0.descriptor.size > $1.descriptor.size }
        }

        return filtered
    }

    private func isImageInUseByRunningContainer(_ image: ContainerImage) -> Bool {
        return containerService.containers.contains { container in
            container.configuration.image.reference == image.reference &&
            container.status.lowercased() == "running"
        }
    }
}
