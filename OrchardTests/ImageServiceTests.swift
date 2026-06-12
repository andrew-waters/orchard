import Testing
import Foundation
@testable import Orchard

// ImageService state transitions, driven against a directly-constructed service.
// `search(_:)` hits a live Docker Hub URL and isn't covered (see the KNOWN-ISSUE on the
// empty-query test) — it has no transport seam.

@MainActor
private func makeImageService(_ backend: MockContainerBackend = MockContainerBackend())
    -> (service: ImageService, alert: AlertCenter) {
    let alert = AlertCenter()
    return (ImageService(backend: backend, alertCenter: alert), alert)
}

// MARK: - load

@MainActor
@Test("Images load: success publishes the list and clears the spinner")
func imageLoadSuccess() async {
    let backend = MockContainerBackend()
    backend.images = [makeImage(reference: "nginx:latest"), makeImage(reference: "redis:7")]
    let (service, _) = makeImageService(backend)

    await service.load(showLoading: true)

    #expect(service.images.map(\.reference) == ["nginx:latest", "redis:7"])
    #expect(service.isImagesLoading == false)
}

@MainActor
@Test(
    "Images load: a failure alerts only when user-initiated",
    arguments: [(showLoading: true, expectsAlert: true), (showLoading: false, expectsAlert: false)]
)
func imageLoadFailure(_ c: (showLoading: Bool, expectsAlert: Bool)) async {
    let backend = MockContainerBackend()
    backend.listImagesError = NotConfigured()
    let (service, alert) = makeImageService(backend)

    await service.load(showLoading: c.showLoading)   // false = background poll → no modal

    #expect((alert.current != nil) == c.expectsAlert)
    #expect(service.isImagesLoading == false)
}

// MARK: - pull

@MainActor
@Test("Images pull: success marks progress completed and pulls the canonical reference")
func imagePullSuccess() async {
    let backend = MockContainerBackend()
    let (service, alert) = makeImageService(backend)

    await service.pull("  nginx:latest  ")   // leading/trailing space trimmed

    #expect(backend.pulledReferences == ["docker.io/library/nginx:latest"])
    #expect(service.pullProgress["docker.io/library/nginx:latest"]?.status == .completed)
    #expect(alert.current == nil)
}

@MainActor
@Test("Images pull: a failure marks progress failed and alerts")
func imagePullFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.pullImageError = NotConfigured()
    let (service, alert) = makeImageService(backend)

    await service.pull("nginx:latest")

    // Match the case, not the (localized, brittle) message.
    if case .failed = service.pullProgress["docker.io/library/nginx:latest"]?.status {} else {
        Issue.record("expected .failed pull status, got \(String(describing: service.pullProgress["docker.io/library/nginx:latest"]?.status))")
    }
    #expect(alert.current != nil)
}

@Test("Image references canonicalize Docker Hub names and preserve explicit registries")
func imageReferenceCanonicalization() {
    #expect(canonicalImageReference("nginx") == "docker.io/library/nginx")
    #expect(canonicalImageReference("nginx:latest") == "docker.io/library/nginx:latest")
    #expect(canonicalImageReference("bitnami/redis:7") == "docker.io/bitnami/redis:7")
    #expect(canonicalImageReference("ghcr.io/acme/app:1") == "ghcr.io/acme/app:1")
    #expect(canonicalImageReference("localhost:5000/acme/app:1") == "localhost:5000/acme/app:1")
}

// MARK: - delete

@MainActor
@Test("Images delete: success removes the image locally and deletes the reference")
func imageDeleteSuccess() async {
    let backend = MockContainerBackend()
    let (service, _) = makeImageService(backend)
    service.images = [makeImage(reference: "gone:1"), makeImage(reference: "keep:1")]

    await service.delete("gone:1")

    #expect(backend.deletedImageReferences == ["gone:1"])
    #expect(service.images.map(\.reference).contains("gone:1") == false)
}

@MainActor
@Test("Images delete: a failure alerts")
func imageDeleteFailureAlerts() async {
    let backend = MockContainerBackend()
    backend.deleteImageError = NotConfigured()
    let (service, alert) = makeImageService(backend)

    await service.delete("stuck:1")

    #expect(alert.current != nil)
}

// MARK: - search guard

@MainActor
@Test("Images search: an empty query clears results")
func imageSearchEmptyQueryClears() async {
    let (service, _) = makeImageService()
    service.searchResults = [
        RegistrySearchResult(name: "stale", description: nil, isOfficial: false, starCount: nil)
    ]

    await service.search("")

    #expect(service.searchResults.isEmpty)
    #expect(service.searchResultsHasMore == false)
    // KNOWN-ISSUE (2026-07-04): search(_:) hardcodes URLSession.shared with no transport
    // seam, so the guard can't be verified to skip the network, and the non-empty query
    // path isn't unit-testable without hitting hub.docker.com.
}
