import Foundation
import SwiftUI
import Darwin

// MARK: - Host architecture (for picking image variant size)

/// Resolved at first access. Honors Rosetta: a translated x86_64 process on Apple
/// Silicon still pulls arm64 container images, so ask the host before falling back to
/// the process slice.
let hostContainerArchitecture: String = {
    var translated: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let rc = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
    if rc == 0 && translated == 1 {
        return "arm64"
    }

    var machineSize: Int = 0
    sysctlbyname("hw.machine", nil, &machineSize, nil, 0)
    guard machineSize > 0 else { return "arm64" }
    var bytes = [CChar](repeating: 0, count: machineSize)
    sysctlbyname("hw.machine", &bytes, &machineSize, nil, 0)
    let raw = String(cString: bytes)
    return raw.contains("arm64") ? "arm64" : "amd64"
}()

/// Normalizes a user-provided image reference to the canonical form
/// `<registry>/<repository>[:tag|@digest]`.
func canonicalImageReference(_ ref: String) -> String {
    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false)
    let firstSegment = segments.first.map(String.init) ?? trimmed
    let looksLikeRegistry =
        segments.count > 1 &&
        (firstSegment.contains(".") ||
         firstSegment.contains(":") ||
         firstSegment == "localhost")

    if looksLikeRegistry { return trimmed }
    if trimmed.contains("/") { return "docker.io/\(trimmed)" }
    return "docker.io/library/\(trimmed)"
}

/// Picks the variant matching this host's platform; falls back to the first variant.
func hostVariantSize(_ variants: [ImageInspection.Variant]) -> Int64 {
    let target = "linux/\(hostContainerArchitecture)"
    if let match = variants.first(where: { $0.platform == target }) {
        return match.size
    }
    return variants.first?.size ?? 0
}

func dockerHubSearchURL(query: String, page: Int) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "hub.docker.com"
    components.path = "/v2/search/repositories/"
    components.queryItems = [
        URLQueryItem(name: "query", value: query),
        URLQueryItem(name: "page_size", value: "25"),
        URLQueryItem(name: "page", value: String(page))
    ]
    return components.url
}

private struct ImageInspectionTimeoutError: LocalizedError {
    var errorDescription: String? { "Image inspection timed out" }
}

private let imageInspectTimeoutNanoseconds: UInt64 = 20_000_000_000

private final class OneShotContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<Value, Error>, with result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return false
        }
        didResume = true
        lock.unlock()

        continuation.resume(with: result)
        return true
    }
}

private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? URLError)?.code == .cancelled
}

private func inspectImageWithTimeout(reference: String, backend: ContainerBackend) async throws -> ImageInspection {
    let race = OneShotContinuation<ImageInspection>()

    return try await withCheckedThrowingContinuation { continuation in
        let inspectionTask = Task {
            do {
                let inspection = try await backend.inspectImage(reference: reference)
                _ = race.resume(continuation, with: .success(inspection))
            } catch {
                _ = race.resume(continuation, with: .failure(error))
            }
        }

        Task {
            do {
                try await Task.sleep(nanoseconds: imageInspectTimeoutNanoseconds)
            } catch {
                return
            }

            inspectionTask.cancel()
            _ = race.resume(continuation, with: .failure(ImageInspectionTimeoutError()))
        }
    }
}

// MARK: - Inspect concurrency limiter

actor InspectGate {
    private let limit: Int
    private var inflight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int = 4) { self.limit = limit }

    func enter() async {
        if inflight < limit {
            inflight += 1
            return
        }
        await withCheckedContinuation { continuation in waiters.append(continuation) }
    }

    func leave() {
        if waiters.isEmpty {
            inflight -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Owns image state and operations: listing, inspection, pulling, deletion, and Docker
/// Hub search. Backed by the XPC image client plus a Docker Hub HTTP search.
@MainActor
final class ImageService: ObservableObject {
    @Published var images: [ContainerImage] = []
    @Published var isImagesLoading = false
    @Published var pullProgress: [String: ImagePullProgress] = [:]
    @Published var imageSizes: [String: ImageSizeStatus] = [:]
    @Published var isSearching = false
    @Published var searchResults: [RegistrySearchResult] = []
    @Published var searchResultsHasMore = false
    @Published var isLoadingMoreSearchResults = false

    private let inspectGate = InspectGate()
    private let imageSizeRetryDelay: TimeInterval = 30
    private var imageSizeRetryAfter: [String: Date] = [:]
    private var searchResultsPage = 0
    private var lastSearchQuery = ""
    private var searchGeneration = 0

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

            let existingRefs = Set(newImages.map(\.reference))
            imageSizes = imageSizes.filter { ref, _ in
                existingRefs.contains(ref)
            }
            imageSizeRetryAfter = imageSizeRetryAfter.filter { ref, _ in
                existingRefs.contains(ref)
            }
            enrichImageSizes(for: newImages)
        } catch {
            self.alertCenter.error(error.localizedDescription, source: showLoading ? .user : .background)
            self.isImagesLoading = false
            Log.containers.error("\(error.localizedDescription)")
        }
    }

    func inspect(reference: String) async throws -> ImageInspection {
        try await backend.inspectImage(reference: reference)
    }

    func sizeText(for image: ContainerImage) -> String {
        switch imageSizes[image.reference] {
        case .known(let size):
            return ByteFormat.string(size)
        case .loading, .none:
            return "…"
        case .failed:
            return "—"
        }
    }

    func sortSize(for image: ContainerImage) -> Int64 {
        if case .known(let size) = imageSizes[image.reference] {
            return size
        }
        return Int64(image.descriptor.size)
    }

    private func enrichImageSizes(for images: [ContainerImage]) {
        let backend = backend
        let inspectGate = inspectGate
        let retryDelay = imageSizeRetryDelay
        let now = Date()

        for image in images {
            let ref = image.reference
            switch imageSizes[ref] {
            case .known, .loading:
                continue
            case .failed:
                if let retryAt = imageSizeRetryAfter[ref], retryAt > now {
                    continue
                }
            case .none:
                break
            }

            imageSizes[ref] = .loading
            Task {
                await inspectGate.enter()
                let result: ImageSizeStatus
                do {
                    let inspection = try await inspectImageWithTimeout(reference: ref, backend: backend)
                    result = .known(hostVariantSize(inspection.variants))
                } catch {
                    result = .failed
                }
                await inspectGate.leave()
                await MainActor.run {
                    self.imageSizes[ref] = result
                    if case .failed = result {
                        self.imageSizeRetryAfter[ref] = Date().addingTimeInterval(retryDelay)
                    } else {
                        self.imageSizeRetryAfter.removeValue(forKey: ref)
                    }
                }
            }
        }
    }

    func dismissPullProgress(_ imageName: String) {
        pullProgress.removeValue(forKey: imageName)
    }

    func pull(_ imageName: String) async {
        let cleanImageName = canonicalImageReference(imageName)
        guard !cleanImageName.isEmpty else { return }

        pullProgress[cleanImageName] = ImagePullProgress(
            imageName: cleanImageName, status: .pulling, progress: 0.0, message: "Pulling image..."
        )

        do {
            try await backend.pullImage(reference: cleanImageName)

            let completedProgress = ImagePullProgress(
                imageName: cleanImageName, status: .completed, progress: 1.0, message: "Pull completed successfully"
            )
            pullProgress[cleanImageName] = completedProgress
            Task { await self.load() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.pullProgress[cleanImageName]?.id == completedProgress.id {
                    self.pullProgress.removeValue(forKey: cleanImageName)
                }
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
            searchResultsHasMore = false
            isSearching = false
            isLoadingMoreSearchResults = false
            searchResultsPage = 0
            lastSearchQuery = ""
            searchGeneration += 1
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        searchResults = []
        searchResultsHasMore = false
        isLoadingMoreSearchResults = false
        searchResultsPage = 0
        lastSearchQuery = query

        await fetchSearchPage(query: query, page: 1, append: false, generation: generation)
        if generation == searchGeneration {
            isSearching = false
        }
    }

    func loadMoreSearchResults() async {
        guard !lastSearchQuery.isEmpty,
              searchResultsHasMore,
              !isLoadingMoreSearchResults
        else { return }

        isLoadingMoreSearchResults = true
        let query = lastSearchQuery
        let generation = searchGeneration
        let page = searchResultsPage + 1
        await fetchSearchPage(query: query, page: page, append: true, generation: generation)
        if generation == searchGeneration {
            isLoadingMoreSearchResults = false
        }
    }

    private func fetchSearchPage(query: String, page: Int, append: Bool, generation: Int) async {
        do {
            guard let url = dockerHubSearchURL(query: query, page: page) else {
                if !append { searchResults = [] }
                searchResultsHasMore = false
                alertCenter.error("Invalid search query")
                return
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            guard generation == searchGeneration, query == lastSearchQuery, !Task.isCancelled else {
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                if !append { searchResults = [] }
                searchResultsHasMore = false
                return
            }

            let newResults: [RegistrySearchResult] = results.compactMap { result in
                guard let name = result["repo_name"] as? String else { return nil }
                let fullName = name.contains("/") ? "docker.io/\(name)" : "docker.io/library/\(name)"

                return RegistrySearchResult(
                    name: fullName,
                    description: result["short_description"] as? String,
                    isOfficial: (result["is_official"] as? Bool) ?? false,
                    starCount: result["star_count"] as? Int
                )
            }

            if append {
                searchResults.append(contentsOf: newResults)
            } else {
                searchResults = newResults
            }
            searchResultsHasMore = json["next"] as? String != nil
            searchResultsPage = page
        } catch {
            guard generation == searchGeneration, query == lastSearchQuery, !isCancellation(error), !Task.isCancelled else {
                return
            }
            alertCenter.error("Failed to search images: \(error.localizedDescription)")
            if !append { searchResults = [] }
            searchResultsHasMore = false
        }
    }

    func clearSearchResults() {
        searchResults = []
        searchResultsHasMore = false
        isLoadingMoreSearchResults = false
        searchResultsPage = 0
        lastSearchQuery = ""
        searchGeneration += 1
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
}
