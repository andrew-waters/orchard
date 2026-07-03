import Testing
import Foundation
@testable import Orchard

// ImageService state transitions, driven through the facade's `imageService`.
// `search(_:)` hits a live Docker Hub URL and isn't covered here (only its empty-query
// guard, which returns before any network call).

// MARK: - load

@MainActor
@Test("Images load: success publishes the list and clears the spinner")
func imageLoadSuccess() async {
    let backend = MockContainerBackend()
    backend.images = [makeImage(reference: "nginx:latest"), makeImage(reference: "redis:7")]
    let service = makeService(backend: backend)

    await service.imageService.load(showLoading: true)

    #expect(service.imageService.images.map(\.reference) == ["nginx:latest", "redis:7"])
    #expect(service.imageService.isImagesLoading == false)
}

@MainActor
@Test("Images load: a user-initiated failure alerts and clears the spinner")
func imageLoadUserFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.listImagesError = NotConfigured()
    let service = makeService(backend: backend)

    await service.imageService.load(showLoading: true)

    #expect(service.alertCenter.current != nil)
    #expect(service.imageService.isImagesLoading == false)
}

@MainActor
@Test("Images load: a background failure stays silent")
func imageLoadBackgroundFailureSilent() async {
    let backend = MockContainerBackend()
    backend.listImagesError = NotConfigured()
    let service = makeService(backend: backend)

    await service.imageService.load(showLoading: false)   // 5s poll → no modal

    #expect(service.alertCenter.current == nil)
    #expect(service.imageService.isImagesLoading == false)
}

// MARK: - pull

@MainActor
@Test("Images pull: success marks progress completed and pulls the trimmed reference")
func imagePullSuccess() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)

    await service.imageService.pull("  nginx:latest  ")   // leading/trailing space trimmed

    #expect(backend.pulledReferences == ["nginx:latest"])
    #expect(service.imageService.pullProgress["nginx:latest"]?.status == .completed)
    #expect(service.alertCenter.current == nil)
}

@MainActor
@Test("Images pull: a failure marks progress failed and alerts")
func imagePullFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.pullImageError = NotConfigured()
    let service = makeService(backend: backend)

    await service.imageService.pull("nginx:latest")

    // Match the case, not the (localized, brittle) message.
    if case .failed = service.imageService.pullProgress["nginx:latest"]?.status {} else {
        Issue.record("expected .failed pull status, got \(String(describing: service.imageService.pullProgress["nginx:latest"]?.status))")
    }
    #expect(service.alertCenter.current != nil)
}

// MARK: - delete

@MainActor
@Test("Images delete: success removes the image locally and deletes the reference")
func imageDeleteSuccess() async {
    let backend = MockContainerBackend()
    let service = makeService(backend: backend)
    service.imageService.images = [makeImage(reference: "gone:1"), makeImage(reference: "keep:1")]

    await service.imageService.delete("gone:1")

    #expect(backend.deletedImageReferences == ["gone:1"])
    #expect(service.imageService.images.map(\.reference).contains("gone:1") == false)
}

@MainActor
@Test("Images delete: a failure alerts")
func imageDeleteFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteImageError = NotConfigured()
    let service = makeService(backend: backend)

    await service.imageService.delete("stuck:1")

    #expect(service.alertCenter.current != nil)
}

// MARK: - search guard / clear

@MainActor
@Test("Images search: an empty query clears results without a network call")
func imageSearchEmptyQueryClears() async {
    let service = makeService()
    service.imageService.searchResults = [
        RegistrySearchResult(name: "stale", description: nil, isOfficial: false, starCount: nil)
    ]

    await service.imageService.search("")

    #expect(service.imageService.searchResults.isEmpty)
    #expect(service.imageService.isSearching == false)
}

@MainActor
@Test("Images clearSearchResults empties the results")
func imageClearSearchResults() {
    let service = makeService()
    service.imageService.searchResults = [
        RegistrySearchResult(name: "nginx", description: nil, isOfficial: true, starCount: 100)
    ]

    service.imageService.clearSearchResults()

    #expect(service.imageService.searchResults.isEmpty)
}
