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

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5)
                .transaction { transaction in
                    transaction.animation = nil
                }

            // Filter controls at bottom
            VStack(alignment: .leading, spacing: 12) {
                // Search & Download button
                Button(action: {
                    showImageSearch = true
                }) {
                    HStack {
                        SwiftUI.Image(systemName: "arrow.down.circle.fill")
                            .font(.body)
                        Text("Search & Download Images")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showImageSearch) {
                    ImageSearchView()
                        .environmentObject(containerService)
                        .frame(minWidth: 700, minHeight: 500)
                }

                Toggle("Only show images in use", isOn: $showOnlyImagesInUse)
                    .toggleStyle(CheckboxToggleStyle())
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Search field
                HStack {
                    SwiftUI.Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter images...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
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
