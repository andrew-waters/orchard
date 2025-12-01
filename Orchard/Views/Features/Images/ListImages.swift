import SwiftUI

struct ImagesListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedImage: String?
    @Binding var lastSelectedImage: String?
    @Binding var searchText: String
    @Binding var showOnlyImagesInUse: Bool
    @Binding var showImageSearch: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            // Images list
            List(selection: $selectedImage) {
                ForEach(filteredImages, id: \.reference) { image in
                    ContainerImageRow(image: image)
                        .tag(image.reference)
                }
            }
            .listStyle(PlainListStyle())
            .animation(.easeInOut(duration: 0.3), value: containerService.images)
            .focused($listFocusedTab, equals: .images)
            .onChange(of: selectedImage) { _, newValue in
                lastSelectedImage = newValue
            }


        }
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

        return filtered
    }
}
