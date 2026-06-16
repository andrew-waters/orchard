import SwiftUI
import AppKit

struct ImageSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var containerService: ContainerService
    @State private var searchQuery: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var directReference: String = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var trimmedDirectReference: String {
        directReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
        }
        .frame(minWidth: 720, idealWidth: 920, minHeight: 560, idealHeight: 640)
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

                TextField("Search for images...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit(performSearchImmediately)
                    .onChange(of: searchQuery) { _, newValue in
                        if newValue.isEmpty {
                            searchTask?.cancel()
                            containerService.clearSearchResults()
                        } else {
                            performSearch()
                        }
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

                Button(action: performSearchImmediately) {
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

            // Pull by reference (for ghcr.io, quay.io, private registries, etc.)
            HStack(spacing: 8) {
                Text("Or pull by reference:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("e.g. ghcr.io/apple/containerization/vminit:0.33.3", text: $directReference)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(pullByReference)

                Button("Pull") {
                    pullByReference()
                }
                .controlSize(.small)
                .disabled(trimmedDirectReference.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func pullByReference() {
        let ref = trimmedDirectReference
        guard !ref.isEmpty else { return }
        Task { await containerService.pullImage(ref) }
        directReference = ""
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 16)], spacing: 16) {
                ForEach(containerService.searchResults) { result in
                    SearchResultRow(result: result)
                        .environmentObject(containerService)
                }
            }
            .padding(20)

            if containerService.searchResultsHasMore {
                ProgressView()
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        Task { await containerService.loadMoreSearchResults() }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Skip the typing debounce and fire the current query right away.
    /// Used by Enter key and the Search button — explicit user intent.
    private func performSearchImmediately() {
        searchTask?.cancel()
        let query = searchQuery
        guard !query.isEmpty else { return }
        searchTask = Task { await containerService.searchImages(query) }
    }
}

struct SearchResultRow: View {
    let result: RegistrySearchResult
    @EnvironmentObject var containerService: ContainerService
    @State private var isHovered = false

    private var isPulling: Bool {
        containerService.pullProgress[result.name] != nil
    }

    private var isAlreadyPulled: Bool {
        containerService.images.contains { image in
            image.reference == result.name
                || image.reference.hasPrefix(result.name + ":")
                || image.reference.hasPrefix(result.name + "@")
        }
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

            // Pull button (or status)
            if isPulling {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(height: 24)
            } else if isAlreadyPulled {
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Already pulled")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
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
    }
}

struct PullProgressRow: View {
    let progress: ImagePullProgress
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SwiftUI.Image(systemName: iconForStatus)
                    .foregroundColor(colorForStatus)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.imageName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(progress.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(progress.message)
                }

                Spacer()

                if progress.status == .pulling {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let onDismiss {
                    Button(action: onDismiss) {
                        SwiftUI.Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }

            if progress.status == .pulling {
                ProgressView()
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
