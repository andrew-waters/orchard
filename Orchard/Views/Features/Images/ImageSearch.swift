import SwiftUI
import AppKit

struct ImageSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var containerService: ContainerService
    @State private var searchQuery: String = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader

            Divider()

            // Search results or empty state
            if searchQuery.isEmpty && containerService.searchResults.isEmpty {
                emptySearchState
            } else if containerService.isSearching {
                loadingState
            } else if !containerService.searchResults.isEmpty {
                searchResultsList
            } else if !searchQuery.isEmpty {
                noResultsState
            } else {
                emptySearchState
            }

            // Active pulls section
            if !containerService.pullProgress.isEmpty {
                Divider()
                activePullsSection
            }
        }
        .frame(width: 920, height: 600)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onDisappear {
            searchTask?.cancel()
            containerService.clearSearchResults()
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 16) {
            HStack {
                SwiftUI.Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Search Container Images")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text("Search Docker Hub for container images to download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            // Search field
            HStack {
                SwiftUI.Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search for images (e.g., nginx, postgres, alpine)...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        performSearch()
                    }

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        containerService.clearSearchResults()
                    }) {
                        SwiftUI.Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    performSearch()
                }) {
                    Text("Search")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchQuery.isEmpty || containerService.isSearching)
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptySearchState: some View {
        VStack(spacing: 20) {
            SwiftUI.Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Search for Container Images")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Find and download images from Docker Hub")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Popular images to try:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    quickSearchButton("nginx")
                    quickSearchButton("postgres")
                    quickSearchButton("redis")
                    quickSearchButton("alpine")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func quickSearchButton(_ query: String) -> some View {
        Button(action: {
            searchQuery = query
            performSearch()
        }) {
            Text(query)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .foregroundColor(.accentColor)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Searching for images...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 20) {
            SwiftUI.Image(systemName: "questionmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No results found")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(280), spacing: 16), count: 3), spacing: 16) {
                ForEach(containerService.searchResults.prefix(12)) { result in
                    SearchResultRow(result: result)
                        .environmentObject(containerService)
                }
            }
            .padding(20)
        }
        .frame(width: 900, height: 400)
    }

    private var activePullsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Active Downloads")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            ForEach(Array(containerService.pullProgress.values), id: \.id) { progress in
                PullProgressRow(progress: progress)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
    }

    private func performSearch() {
        // Cancel any existing search
        searchTask?.cancel()

        // Start new search with debounce
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second debounce

            if !Task.isCancelled {
                await containerService.searchImages(searchQuery)
            }
        }
    }
}

struct SearchResultRow: View {
    let result: RegistrySearchResult
    @EnvironmentObject var containerService: ContainerService
    @State private var isHovered = false
    @State private var showRunContainer = false

    private var isPulling: Bool {
        containerService.pullProgress[result.name] != nil
    }

    private var isAlreadyPulled: Bool {
        containerService.images.contains { $0.reference.contains(result.displayName) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and name
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: result.isOfficial ? "checkmark.seal.fill" : "cube.transparent")
                    .font(.title3)
                    .foregroundColor(result.isOfficial ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Metadata
                    HStack(spacing: 6) {
                        if result.isOfficial {
                            Text("Official")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue)
                                .cornerRadius(2)
                        }

                        if let stars = result.starCount, stars > 0 {
                            HStack(spacing: 2) {
                                SwiftUI.Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                Text("\(stars)")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.orange)
                        }

                        Spacer()
                    }
                }
            }

            // Description
            if let description = result.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            // Pull/Run button
            if isPulling {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(height: 24)
            } else if isAlreadyPulled {
                Button(action: {
                    showRunContainer = true
                }) {
                    Text("Run")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(Color.green)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    Task {
                        await containerService.pullImage(result.name)
                    }
                }) {
                    Text("Pull")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 280, height: 140)
        .background(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.8 : 0.3))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
        .sheet(isPresented: $showRunContainer) {
            RunContainerView(imageName: result.name)
                .environmentObject(containerService)
        }
    }
}

struct PullProgressRow: View {
    let progress: ImagePullProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SwiftUI.Image(systemName: iconForStatus)
                    .foregroundColor(colorForStatus)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.imageName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(progress.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if progress.status == .pulling {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            if progress.status == .pulling {
                ProgressView(value: progress.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding()
        .background(backgroundForStatus)
        .cornerRadius(8)
    }

    private var iconForStatus: String {
        switch progress.status {
        case .pulling:
            return "arrow.down.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var colorForStatus: Color {
        switch progress.status {
        case .pulling:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var backgroundForStatus: Color {
        switch progress.status {
        case .pulling:
            return Color.blue.opacity(0.1)
        case .completed:
            return Color.green.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        }
    }
}

#Preview {
    ImageSearchView()
        .environmentObject(ContainerService())
        .frame(width: 700, height: 600)
}
