import Foundation

/// One Kubernetes version offered by the Create Cluster sheet: a `kindest/node` image pinned
/// by digest, because kind rebuilds node images per kind release and the tag alone does not
/// say which build you get.
struct K8sNodeImageOption: Identifiable, Equatable, Hashable {
    /// The image tag, e.g. `v1.35.8`.
    let version: String
    /// The full reference passed to `--node-image`, e.g. `docker.io/kindest/node:v1.35.8@sha256:<digest>`.
    let reference: String

    var id: String { reference }
}

/// Builds the version list for `container k8s create --node-image`.
///
/// Since container 1.5.0 the control plane is configured from the node image's tag
/// (apple/container#2271); before that it was always the plugin default's version, so a
/// different image ran mismatched components. That makes choosing a version meaningful, and
/// it is also why 1.5.0 rejects an image with no tag.
enum K8sNodeImageCatalog {
    static let repository = "docker.io/kindest/node"

    /// Docker Hub's tag API rather than the registry's `/tags/list`: it returns digests and can
    /// order by date, where the registry returns every tag since 2018 as bare names.
    static let tagsURL = URL(string: "https://hub.docker.com/v2/repositories/kindest/node/tags?page_size=100&ordering=last_updated")!

    /// The oldest minor the plugin can bootstrap: it writes a `kubeadm.k8s.io/v1beta4` config,
    /// which kubeadm understands from 1.31.
    static let oldestSupportedMinor = 31

    /// The plugin's default image, read from `container k8s create --help` so it follows the
    /// installed plugin instead of a copy that goes stale. The help wraps the reference onto
    /// its own line, so whitespace after "default:" can include a newline.
    static func parsePluginDefault(helpText: String) -> String? {
        guard let match = helpText.firstMatch(of: #/Node image reference \(default:\s+([^\s)]+)\)/#) else {
            return nil
        }
        return String(match.1)
    }

    /// The tag of a `kindest/node` reference, e.g. `v1.35.5` from `docker.io/kindest/node:v1.35.5@sha256:<digest>`.
    static func tag(of reference: String) -> String? {
        let nameAndTag = reference.split(separator: "@", maxSplits: 1).first.map(String.init) ?? reference
        // A colon before the last slash is a registry port, not a tag.
        let lastComponent = nameAndTag.split(separator: "/").last.map(String.init) ?? nameAndTag
        guard let colon = lastComponent.lastIndex(of: ":") else { return nil }
        let tag = lastComponent[lastComponent.index(after: colon)...]
        return tag.isEmpty ? nil : String(tag)
    }

    struct HubTag: Decodable, Equatable {
        let name: String
        let digest: String?
    }

    private struct HubTagPage: Decodable {
        let results: [HubTag]
    }

    static func parseHubTags(_ data: Data) throws -> [HubTag] {
        try JSONDecoder().decode(HubTagPage.self, from: data).results
    }

    /// The newest patch of each supported minor, newest minor first. Pre-releases, tags
    /// without a digest to pin, and anything older than `oldestSupportedMinor` are dropped.
    static func options(from tags: [HubTag]) -> [K8sNodeImageOption] {
        var newestByMinor: [Int: (patch: Int, option: K8sNodeImageOption)] = [:]
        for tag in tags {
            guard let digest = tag.digest, !digest.isEmpty,
                  let match = tag.name.wholeMatch(of: #/v1\.(\d+)\.(\d+)/#),
                  let minor = Int(match.1), let patch = Int(match.2),
                  minor >= oldestSupportedMinor
            else { continue }
            if let existing = newestByMinor[minor], existing.patch >= patch { continue }
            let option = K8sNodeImageOption(version: tag.name, reference: "\(repository):\(tag.name)@\(digest)")
            newestByMinor[minor] = (patch, option)
        }
        return newestByMinor.keys.sorted(by: >).compactMap { newestByMinor[$0]?.option }
    }

    static func fetchTags() async throws -> [HubTag] {
        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try parseHubTags(data)
    }
}
