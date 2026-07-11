import Foundation
import SwiftUI

/// Owns image state and operations: listing, inspection, pulling, deletion, and Docker
/// Hub search. Backed by the XPC image client plus a Docker Hub HTTP search.
@MainActor
final class ImageService: ObservableObject {
    @Published var images: [ContainerImage] = []
    @Published var isImagesLoading = false
    @Published var pullProgress: [String: ImagePullProgress] = [:]
    @Published var isSearching = false
    @Published var searchResults: [RegistrySearchResult] = []

    private let backend: ContainerBackend
    private let alertCenter: AlertCenter

    init(backend: ContainerBackend, alertCenter: AlertCenter) {
        self.backend = backend
        self.alertCenter = alertCenter
    }

    /// Refresh the image list. Driven by the 5s poll, so failures are logged, not
    /// modal — pull/delete (user actions) alert on their own.
    func load(showLoading: Bool = false) async {
        if showLoading {
            isImagesLoading = true
        }

        do {
            let newImages = try await backend.listImages()
            // Only republish (and animate) when the list actually changed — otherwise
            // every 5s tick invalidates the whole view tree for nothing.
            if newImages != self.images {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.images = newImages
                }
            }
            self.isImagesLoading = false
        } catch {
            self.alertCenter.error(error.localizedDescription, source: showLoading ? .user : .background)
            self.isImagesLoading = false
            Log.containers.error("\(error.localizedDescription)")
        }
    }

    func inspect(reference: String) async throws -> ImageInspection {
        try await backend.inspectImage(reference: reference)
    }

    func pull(_ imageName: String) async {
        let cleanImageName = imageName.trimmingCharacters(in: .whitespacesAndNewlines)

        pullProgress[cleanImageName] = ImagePullProgress(
            imageName: cleanImageName, status: .pulling, progress: 0.0, message: "Pulling image..."
        )

        do {
            try await backend.pullImage(reference: cleanImageName)

            pullProgress[cleanImageName] = ImagePullProgress(
                imageName: cleanImageName, status: .completed, progress: 1.0, message: "Pull completed successfully"
            )
            Task { await self.load() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.pullProgress.removeValue(forKey: cleanImageName)
            }
        } catch {
            let errorMsg = error.localizedDescription
            pullProgress[cleanImageName] = ImagePullProgress(
                imageName: cleanImageName, status: .failed(errorMsg), progress: 0.0, message: "Pull failed: \(errorMsg)"
            )
            self.alertCenter.error("Failed to pull image: \(errorMsg)")
        }
    }

    func search(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        do {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let urlString = "https://hub.docker.com/v2/search/repositories/?query=\(encodedQuery)&page_size=25"

            guard let url = URL(string: urlString) else {
                isSearching = false
                self.alertCenter.error("Invalid search query")
                return
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let results = parseDockerHubSearch(data: data)
            self.searchResults = results
            self.isSearching = false
        } catch {
            self.alertCenter.error("Failed to search images: \(error.localizedDescription)")
            self.isSearching = false
            self.searchResults = []
        }
    }

    func clearSearchResults() {
        searchResults = []
    }

    func delete(_ imageReference: String) async {
        self.alertCenter.dismiss()

        do {
            try await backend.deleteImage(reference: imageReference)
            self.images.removeAll { $0.reference == imageReference }
            Task { await self.load() }
        } catch {
            self.alertCenter.error("Failed to delete image: \(error.localizedDescription)")
        }
    }
    func deleteImages(_ references: [String]) async {
        var deletedCount = 0
        var failedCount = 0
        var lastError: Error?
        for reference in references {
            do {
                try await backend.deleteImage(reference: reference)
                deletedCount += 1
            } catch {
                failedCount += 1
                lastError = error
            }
        }
        await load()
        if failedCount > 0 {
            alertCenter.error("Failed to delete \(failedCount) image(s): \(lastError?.localizedDescription ?? "Unknown error")")
        }
    }

}
